package agentsession

import (
	"context"
	"sync"
)

type processProof struct {
	pid    int
	token  string
	cancel context.CancelFunc
}

type ProcessLiveness struct {
	ctx    context.Context
	mu     sync.Mutex
	proofs map[string]processProof
	exited func(string)
}

func NewProcessLiveness(ctx context.Context, exited func(string)) *ProcessLiveness {
	return &ProcessLiveness{ctx: ctx, proofs: make(map[string]processProof), exited: exited}
}

func (l *ProcessLiveness) Observe(event Event) bool {
	if event.ProcessID <= 1 || event.ProcessStart == "" {
		return false
	}
	observed, err := ProcessStartToken(event.ProcessID)
	if err != nil || observed != event.ProcessStart {
		return false
	}
	id := Identity(event.Provider, event.SessionID)
	l.mu.Lock()
	defer l.mu.Unlock()
	if existing, ok := l.proofs[id]; ok {
		if existing.pid == event.ProcessID && existing.token == event.ProcessStart {
			return true
		}
		existing.cancel()
	}
	watchCtx, cancel := context.WithCancel(l.ctx)
	l.proofs[id] = processProof{pid: event.ProcessID, token: event.ProcessStart, cancel: cancel}
	go func(pid int, token string) {
		err := WatchExactProcessExit(watchCtx, pid, token)
		if err != nil || watchCtx.Err() != nil {
			return
		}
		l.mu.Lock()
		proof, ok := l.proofs[id]
		if ok && proof.pid == pid && proof.token == token {
			delete(l.proofs, id)
		}
		l.mu.Unlock()
		if ok && l.exited != nil {
			l.exited(id)
		}
	}(event.ProcessID, event.ProcessStart)
	return true
}

func (l *ProcessLiveness) Remove(id string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if proof, ok := l.proofs[id]; ok {
		proof.cancel()
		delete(l.proofs, id)
	}
}

func (l *ProcessLiveness) Close() {
	l.mu.Lock()
	defer l.mu.Unlock()
	for id, proof := range l.proofs {
		proof.cancel()
		delete(l.proofs, id)
	}
}

func (l *ProcessLiveness) Count() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.proofs)
}
