package agentsession

import (
	"context"
	"errors"
	"sync"
	"time"
)

const codexQuietPeriod = 120 * time.Second

type CodexControllerOptions struct {
	Environment  map[string]string
	QuietPeriod  time.Duration
	Now          func() time.Time
	Emit         func(Event)
	State        func(string, string)
	Acknowledged func(time.Time)
}

type CodexController struct {
	ctx       context.Context
	options   CodexControllerOptions
	refreshMu sync.Mutex
	mu        sync.Mutex
	client    *codexClient
	quiet     *time.Timer
	lastUse   time.Time
	closed    bool
	requests  chan struct{}
	done      chan struct{}
	doneOnce  sync.Once
}

func NewCodexController(ctx context.Context, options CodexControllerOptions) *CodexController {
	if options.QuietPeriod <= 0 {
		options.QuietPeriod = codexQuietPeriod
	}
	if options.Now == nil {
		options.Now = func() time.Time { return time.Now().UTC() }
	}
	controller := &CodexController{
		ctx: ctx, options: options, requests: make(chan struct{}, 1), done: make(chan struct{}),
	}
	go controller.runRequests()
	return controller
}

func (c *CodexController) RequestRefresh() {
	select {
	case <-c.done:
		return
	case c.requests <- struct{}{}:
	default:
	}
}

func (c *CodexController) runRequests() {
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-c.done:
			return
		case <-c.requests:
			_ = c.Refresh(c.ctx)
		}
	}
}

func (c *CodexController) Refresh(ctx context.Context) error {
	c.refreshMu.Lock()
	defer c.refreshMu.Unlock()
	client, err := c.ensureClient()
	if err != nil {
		c.report("disconnected", codexErrorCode(err))
		return err
	}
	c.report("connected", "")
	if err := client.discover(ctx); err != nil {
		c.report("degraded", codexErrorCode(err))
		c.stopClient(client)
		return err
	}
	now := c.options.Now()
	if c.options.Acknowledged != nil {
		c.options.Acknowledged(now)
	}
	c.scheduleQuiet(now)
	return nil
}

func (c *CodexController) Stop() {
	c.doneOnce.Do(func() { close(c.done) })
	c.refreshMu.Lock()
	defer c.refreshMu.Unlock()
	c.mu.Lock()
	c.closed = true
	if c.quiet != nil {
		c.quiet.Stop()
		c.quiet = nil
	}
	client := c.client
	c.client = nil
	c.mu.Unlock()
	if client != nil {
		select {
		case <-c.ctx.Done():
			client.stopNow()
		default:
			client.stop()
		}
	}
	c.report("stopped", "")
}

func (c *CodexController) Running() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.client != nil && c.client.running()
}

func (c *CodexController) ensureClient() (*codexClient, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil, context.Canceled
	}
	if c.client != nil && c.client.running() {
		return c.client, nil
	}
	if c.client != nil {
		c.client.stop()
		c.client = nil
	}
	client, err := startCodexClient(c.ctx, c.options.Environment, c.options.Emit)
	if err != nil {
		return nil, err
	}
	c.client = client
	c.lastUse = c.options.Now()
	return client, nil
}

func (c *CodexController) scheduleQuiet(now time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.lastUse = now
	if c.quiet != nil {
		c.quiet.Stop()
	}
	c.quiet = time.AfterFunc(c.options.QuietPeriod, c.stopAfterQuiet)
}

func (c *CodexController) stopAfterQuiet() {
	c.refreshMu.Lock()
	defer c.refreshMu.Unlock()
	c.mu.Lock()
	if c.closed || c.client == nil {
		c.mu.Unlock()
		return
	}
	remaining := c.options.QuietPeriod - c.options.Now().Sub(c.lastUse)
	if remaining > 0 {
		c.quiet = time.AfterFunc(remaining, c.stopAfterQuiet)
		c.mu.Unlock()
		return
	}
	client := c.client
	c.client = nil
	c.quiet = nil
	c.mu.Unlock()
	client.stop()
	c.report("idle", "")
}

func (c *CodexController) stopClient(client *codexClient) {
	c.mu.Lock()
	if c.client == client {
		c.client = nil
	}
	if c.quiet != nil {
		c.quiet.Stop()
		c.quiet = nil
	}
	c.mu.Unlock()
	client.stop()
}

func (c *CodexController) report(state, code string) {
	if c.options.State != nil {
		c.options.State(state, code)
	}
}

func codexErrorCode(err error) string {
	switch {
	case err == nil:
		return ""
	case errors.Is(err, context.Canceled), errors.Is(err, context.DeadlineExceeded):
		return "request_cancelled"
	case errors.Is(err, errCodexUnavailable):
		return "client_unavailable"
	case errors.Is(err, errCodexUnsupported):
		return "unsupported_method"
	default:
		return "transport_error"
	}
}
