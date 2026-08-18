package agentsession

import (
	"context"
	"errors"
	"time"
)

type rolloutCommand struct {
	seed Event
}

type rolloutTrigger struct {
	path      string
	discovery bool
}

type RolloutManagerOptions struct {
	Home     string
	Now      func() time.Time
	Emit     func(Event)
	Error    func(string)
	Watchers func(int)
	Rejected func()
}

type RolloutManager struct {
	ctx      context.Context
	commands chan rolloutCommand
	releases chan string
	refresh  chan struct{}
	done     chan struct{}
}

func StartRolloutManager(ctx context.Context, options RolloutManagerOptions) *RolloutManager {
	if options.Now == nil {
		options.Now = func() time.Time { return time.Now().UTC() }
	}
	manager := &RolloutManager{
		ctx: ctx, commands: make(chan rolloutCommand, 256), releases: make(chan string, maxSessions),
		refresh: make(chan struct{}, 1), done: make(chan struct{}),
	}
	go manager.run(options)
	return manager
}

func (m *RolloutManager) Admit(seed Event) bool {
	select {
	case m.commands <- rolloutCommand{seed: seed}:
		return true
	case <-m.ctx.Done():
		return false
	default:
		return false
	}
}

func (m *RolloutManager) Refresh() {
	select {
	case m.refresh <- struct{}{}:
	default:
	}
}

func (m *RolloutManager) Release(id string) {
	select {
	case m.releases <- id:
	case <-m.ctx.Done():
	}
}

func (m *RolloutManager) Wait() { <-m.done }

func (m *RolloutManager) run(options RolloutManagerOptions) {
	defer close(m.done)
	triggers := make(chan rolloutTrigger, 128)
	watchDone := make(chan string, maxCodexRolloutWatches)
	directoryChanged := make(chan struct{}, 1)
	directoryDone := make(chan struct{}, 1)
	reporter := newWatcherReporter(options.Watchers)
	defer reporter.stop()
	registry := NewRolloutRegistry(m.ctx, func(watchCtx context.Context, path string) {
		go watchManagedPath(watchCtx, path, triggers, watchDone)
	}, func(used int) { reporter.submit(used, options.Now()) })
	defer registry.Close()
	var directoryCancel context.CancelFunc
	bindDirectory := func() {
		if directoryCancel != nil {
			directoryCancel()
		}
		target := watchableCodexDirectory(options.Home, options.Now())
		if target == "" {
			directoryCancel = nil
			return
		}
		watchCtx, cancel := context.WithCancel(m.ctx)
		directoryCancel = cancel
		go watchCodexDirectory(watchCtx, target, directoryChanged, directoryDone)
	}
	defer func() {
		if directoryCancel != nil {
			directoryCancel()
		}
	}()
	discoveryRemaining := int64(maxDiscoveryBytes)
	immediate := make(chan struct{})
	close(immediate)
	work := make([]string, 0, maxCodexRolloutWatches)
	pendingWork := make(map[string]rolloutTrigger, maxCodexRolloutWatches)
	enqueueWork := func(trigger rolloutTrigger) {
		if existing, ok := pendingWork[trigger.path]; ok {
			existing.discovery = existing.discovery || trigger.discovery
			pendingWork[trigger.path] = existing
			return
		}
		pendingWork[trigger.path] = trigger
		work = append(work, trigger.path)
	}
	discover := func() {
		discoveryRemaining = maxDiscoveryBytes
		for _, candidate := range discoverCodexRollouts(options.Home, options.Now()) {
			_, _ = registry.Admit(candidate.path, candidate.seed, true, options.Now())
			enqueueWork(rolloutTrigger{path: candidate.path, discovery: true})
		}
	}
	bindDirectory()
	discover()
	dayTimer := time.NewTimer(nextLocalDay(options.Now()).Sub(options.Now()))
	defer dayTimer.Stop()
	processTrigger := func(trigger rolloutTrigger) {
		entry, ok := registry.Entry(trigger.path)
		if !ok {
			return
		}
		budget := int64(rolloutTurnBytes)
		if trigger.discovery {
			if discoveryRemaining < rolloutChunkBytes+4*1024 {
				return
			}
			if discoveryRemaining < budget {
				budget = discoveryRemaining
			}
		}
		event, changed, more, readBytes, err := entry.cursor.Advance(options.Now(), budget, rolloutTurnRows)
		if trigger.discovery {
			discoveryRemaining -= readBytes
		}
		if err != nil {
			registry.Remove(trigger.path)
			code := "rollout_unavailable"
			if errors.Is(err, ErrRolloutIdentityMismatch) {
				code = "identity_mismatch"
			}
			rejectRollout(options, code)
			return
		}
		if changed {
			event.rolloutCaughtUp = !more
			registry.Update(trigger.path, event, options.Now())
			if options.Emit != nil {
				options.Emit(event)
			}
			if event.Phase == PhaseEnded {
				registry.Remove(trigger.path)
			}
		}
		if more {
			enqueueWork(trigger)
		}
	}
	for {
		var workReady <-chan struct{}
		if len(work) > 0 {
			workReady = immediate
		}
		select {
		case <-m.ctx.Done():
			return
		case <-reporter.deadline:
			reporter.flush(options.Now())
		case <-workReady:
			path := work[0]
			work = work[1:]
			trigger := pendingWork[path]
			delete(pendingWork, path)
			processTrigger(trigger)
		case command := <-m.commands:
			path, err := SafeCodexRolloutPath(command.seed.RolloutPath, options.Home)
			if err != nil {
				rejectRollout(options, "unsafe_rollout_path")
				continue
			}
			_, _ = registry.Admit(path, command.seed, false, options.Now())
			enqueueWork(rolloutTrigger{path: path})
		case <-m.refresh:
			bindDirectory()
			discover()
		case id := <-m.releases:
			registry.ReleaseIdentity(id)
		case trigger := <-triggers:
			processTrigger(trigger)
		case path := <-watchDone:
			registry.Remove(path)
		case <-directoryChanged:
			bindDirectory()
			discover()
		case <-directoryDone:
			bindDirectory()
		case <-dayTimer.C:
			bindDirectory()
			discover()
			dayTimer.Reset(nextLocalDay(options.Now()).Sub(options.Now()))
		}
	}
}

func watchManagedPath(ctx context.Context, path string, triggers chan<- rolloutTrigger, done chan<- string) {
	err := WatchPath(ctx, path, func() { sendRolloutTrigger(ctx, triggers, rolloutTrigger{path: path}) })
	if err == nil && ctx.Err() != nil {
		return
	}
	select {
	case done <- path:
	case <-ctx.Done():
	}
}

func sendRolloutTrigger(ctx context.Context, output chan<- rolloutTrigger, trigger rolloutTrigger) {
	select {
	case output <- trigger:
	case <-ctx.Done():
	}
}

func watchCodexDirectory(ctx context.Context, path string, changed chan<- struct{}, done chan<- struct{}) {
	err := WatchPath(ctx, path, func() {
		select {
		case changed <- struct{}{}:
		default:
		}
	})
	if err == nil && ctx.Err() != nil {
		return
	}
	select {
	case done <- struct{}{}:
	case <-ctx.Done():
	}
}

func rejectRollout(options RolloutManagerOptions, code string) {
	if options.Rejected != nil {
		options.Rejected()
	}
	if options.Error != nil {
		options.Error(code)
	}
}
