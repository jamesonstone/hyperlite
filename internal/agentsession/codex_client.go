package agentsession

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"strconv"
	"sync"
	"time"
)

var (
	errCodexUnavailable = errors.New("codex app-server is unavailable")
	errCodexUnsupported = errors.New("codex app-server method is unsupported")
)

const maxCodexDiscoveryThreads = 200

type codexClient struct {
	command   *exec.Cmd
	stdin     io.WriteCloser
	encoder   *json.Encoder
	responses chan codexRPCMessage
	done      chan struct{}
	stopOnce  sync.Once
	requestMu sync.Mutex
	nextID    int
	emit      func(Event)
}

func startCodexClient(ctx context.Context, environment map[string]string, emit func(Event)) (*codexClient, error) {
	executable := resolveCodexExecutable(environment)
	if executable == "" {
		return nil, errCodexUnavailable
	}
	command := exec.CommandContext(ctx, executable, "app-server", "--stdio")
	command.Env = mergeEnvironment(os.Environ(), environment)
	stdin, err := command.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		_ = stdin.Close()
		return nil, err
	}
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		_ = stdin.Close()
		return nil, err
	}
	client := &codexClient{
		command: command, stdin: stdin, encoder: json.NewEncoder(stdin),
		responses: make(chan codexRPCMessage, 16), done: make(chan struct{}), nextID: 1, emit: emit,
	}
	go client.read(stdout)
	go func() {
		_ = command.Wait()
		client.stopOnce.Do(func() { close(client.done) })
	}()
	initializeCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if _, err := client.request(initializeCtx, "initialize", map[string]any{
		"clientInfo": map[string]any{"name": "hyperlite", "title": "Hyperlite", "version": "2"},
	}); err != nil {
		client.stop()
		return nil, err
	}
	if err := client.encoder.Encode(map[string]any{"method": "initialized"}); err != nil {
		client.stop()
		return nil, err
	}
	return client, nil
}

func (c *codexClient) discover(ctx context.Context) error {
	cursor := ""
	discovered := 0
	for page := 0; page < 10; page++ {
		params := map[string]any{
			"limit": 100, "sortKey": "recency_at", "sortDirection": "desc",
			"archived": false, "useStateDbOnly": true, "sourceKinds": codexSourceKinds(),
		}
		if cursor != "" {
			params["cursor"] = cursor
		}
		response, err := c.request(ctx, "thread/list", params)
		if err != nil {
			return err
		}
		for _, thread := range objectSlice(response.Result["data"]) {
			if event, ok := codexThreadEvent(thread, time.Now().UTC()); ok && c.emit != nil {
				c.emit(event)
				discovered++
				if discovered >= maxCodexDiscoveryThreads {
					return nil
				}
			}
		}
		cursor = firstString(response.Result, "nextCursor", "next_cursor")
		if cursor == "" {
			return nil
		}
	}
	return nil
}

func (c *codexClient) request(ctx context.Context, method string, params map[string]any) (codexRPCMessage, error) {
	c.requestMu.Lock()
	defer c.requestMu.Unlock()
	id := c.nextID
	c.nextID++
	if err := c.encoder.Encode(map[string]any{"id": id, "method": method, "params": params}); err != nil {
		return codexRPCMessage{}, err
	}
	for {
		select {
		case <-ctx.Done():
			return codexRPCMessage{}, ctx.Err()
		case <-c.done:
			select {
			case response := <-c.responses:
				if rpcID(response.ID) != strconv.Itoa(id) {
					continue
				}
				if len(response.Error) > 0 {
					return codexRPCMessage{}, errCodexUnsupported
				}
				return response, nil
			default:
				return codexRPCMessage{}, io.EOF
			}
		case response := <-c.responses:
			if rpcID(response.ID) != strconv.Itoa(id) {
				continue
			}
			if len(response.Error) > 0 {
				return codexRPCMessage{}, errCodexUnsupported
			}
			return response, nil
		}
	}
}

func (c *codexClient) read(output io.Reader) {
	reader := bufio.NewScanner(output)
	reader.Buffer(make([]byte, rolloutChunkBytes), maxAppServerMessage)
	for reader.Scan() {
		message, ok := decodeCodexLine(reader.Bytes())
		if !ok {
			continue
		}
		if message.Method != "" {
			handleCodexNotification(message, c.emit)
			continue
		}
		select {
		case c.responses <- message:
		case <-c.done:
			return
		}
	}
	if reader.Err() != nil {
		c.stopNow()
	}
}

func (c *codexClient) running() bool {
	if c.command == nil {
		return false
	}
	select {
	case <-c.done:
		return false
	default:
		return c.command.Process != nil
	}
}

func (c *codexClient) stop() {
	if c.stdin != nil {
		_ = c.stdin.Close()
	}
	if c.command.Process != nil && c.running() {
		_ = c.command.Process.Signal(os.Interrupt)
		select {
		case <-c.done:
		case <-time.After(2 * time.Second):
			_ = c.command.Process.Kill()
			<-c.done
		}
	}
}

func (c *codexClient) stopNow() {
	if c.stdin != nil {
		_ = c.stdin.Close()
	}
	if c.command == nil {
		c.stopOnce.Do(func() { close(c.done) })
		return
	}
	if c.command.Process != nil && c.running() {
		_ = c.command.Process.Kill()
		<-c.done
	}
}

func codexSourceKinds() []string {
	return []string{"cli", "vscode", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther"}
}
