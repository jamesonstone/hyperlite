package agentsession

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"
)

type ServiceOptions struct {
	SocketPath       string
	Home             string
	BridgePath       string
	Environment      map[string]string
	DisableCodex     bool
	CodexQuietPeriod time.Duration
	Now              func() time.Time
}

type inboundEvent struct {
	event Event
	conn  net.Conn
}

type pendingResponse struct {
	sessionID string
	requestID string
	provider  string
	conn      net.Conn
}

type pendingClosure struct {
	key  string
	conn net.Conn
}

type healthSignal struct {
	kind    string
	profile string
	state   string
	code    string
	used    int
	at      time.Time
}

type safeEncoder struct {
	mu      sync.Mutex
	encoder *json.Encoder
}

func (e *safeEncoder) encode(value any) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.encoder.Encode(value)
}

func RunService(ctx context.Context, in io.Reader, out, errOut io.Writer, options ServiceOptions) error {
	serviceCtx, cancel := context.WithCancel(ctx)
	if options.Now == nil {
		options.Now = func() time.Time { return time.Now().UTC() }
	}
	if options.SocketPath == "" {
		options.SocketPath = RuntimeSocketPath(serviceEnvironment(options))
	}
	listener, err := PrepareRuntimeSocket(options.SocketPath)
	if err != nil {
		cancel()
		return err
	}
	defer func() {
		cancel()
		_ = listener.Close()
		_ = os.Remove(options.SocketPath)
	}()
	events := make(chan inboundEvent, 128)
	inputs := make(chan serviceInput, 32)
	closedResponses := make(chan pendingClosure, maxPendingActions*4)
	processExits := make(chan string, maxSessions)
	healthSignals := make(chan healthSignal, 64)
	selfTests := make(chan selfTestResult, 16)
	readErrors := make(chan error, 4)
	go acceptEvents(serviceCtx, listener, events, readErrors)
	closeOwnerInputOnCancel(serviceCtx, in)
	go readServiceInput(serviceCtx, in, inputs, readErrors)

	integrations := DetectIntegrations(options.Home, options.BridgePath)
	runtime := newSessionRuntime(serviceCtx, options, out, errOut, integrations)
	runtime.closedResponses = closedResponses
	runtime.processExits = processExits
	runtime.selfTests = selfTests
	runtime.healthSignals = healthSignals
	runtime.liveness = NewProcessLiveness(serviceCtx, func(id string) {
		select {
		case processExits <- id:
		case <-serviceCtx.Done():
		}
	})

	if !options.DisableCodex {
		runtime.rollouts = StartRolloutManager(serviceCtx, RolloutManagerOptions{
			Home: options.Home, Now: options.Now,
			Emit: func(event Event) {
				select {
				case events <- inboundEvent{event: event}:
				case <-serviceCtx.Done():
				}
			},
			Watchers: func(used int) {
				sendHealthSignal(serviceCtx, healthSignals, healthSignal{kind: "watchers", profile: "codex", used: used})
			},
			Rejected: func() {
				sendHealthSignal(serviceCtx, healthSignals, healthSignal{kind: "rejected", profile: "codex", code: "rollout_rejected"})
			},
		})
		runtime.codex = NewCodexController(serviceCtx, CodexControllerOptions{
			Environment: serviceEnvironment(options), QuietPeriod: options.CodexQuietPeriod, Now: options.Now,
			Emit: func(event Event) {
				select {
				case events <- inboundEvent{event: event}:
				case <-serviceCtx.Done():
				}
			},
			State: func(state, code string) {
				sendHealthSignal(serviceCtx, healthSignals, healthSignal{
					kind: "connection", profile: "codex", state: state, code: code,
				})
			},
			Acknowledged: func(at time.Time) {
				sendHealthSignal(serviceCtx, healthSignals, healthSignal{kind: "ack", profile: "codex", at: at})
			},
		})
		runtime.codex.RequestRefresh()
	}
	defer func() {
		cancel()
		runtime.close()
	}()

	initial := runtime.store.SetIntegrations(integrations)
	runtime.scheduler.RecordInitial(options.Now())
	if err := runtime.emitter.encode(initial); err != nil {
		return fmt.Errorf("emit initial agent snapshot: %w", err)
	}
	for _, health := range runtime.health.All() {
		if err := runtime.emitter.encode(health); err != nil {
			return fmt.Errorf("emit initial integration health: %w", err)
		}
	}

	var timer *time.Timer
	var deadline <-chan time.Time
	resetTimer := func() {
		if timer != nil && !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		next, ok := runtime.nextDeadline()
		if !ok {
			timer, deadline = nil, nil
			return
		}
		delay := next.Sub(options.Now())
		if delay < 0 {
			delay = 0
		}
		timer = time.NewTimer(delay)
		deadline = timer.C
	}
	defer func() {
		if timer != nil {
			timer.Stop()
		}
	}()
	resetTimer()

	for {
		select {
		case <-serviceCtx.Done():
			return nil
		case received := <-events:
			if err := runtime.handleEvent(received); err != nil {
				return err
			}
			resetTimer()
		case input := <-inputs:
			if err := runtime.handleInput(input); err != nil {
				return err
			}
			resetTimer()
		case closed := <-closedResponses:
			if err := runtime.handleClosedResponse(closed); err != nil {
				return err
			}
			resetTimer()
		case id := <-processExits:
			if err := runtime.handleProcessExit(id); err != nil {
				return err
			}
			resetTimer()
		case signal := <-healthSignals:
			if err := runtime.handleHealth(signal); err != nil {
				return err
			}
		case result := <-selfTests:
			if result.err != nil {
				if err := runtime.emitSelfTest(result.profile, "failed", "bridge_unavailable"); err != nil {
					return err
				}
			}
		case <-deadline:
			if err := runtime.handleDeadline(); err != nil {
				return err
			}
			resetTimer()
		case readErr := <-readErrors:
			if readErr == io.EOF {
				return nil
			}
			if readErr != nil {
				_, _ = fmt.Fprintln(errOut, "agent session transport unavailable: transport_error")
				var ownerErr ownerInputError
				if errors.As(readErr, &ownerErr) {
					return ownerErr
				}
			}
		}
	}
}

func sendHealthSignal(ctx context.Context, output chan<- healthSignal, signal healthSignal) {
	select {
	case output <- signal:
	case <-ctx.Done():
	}
}
