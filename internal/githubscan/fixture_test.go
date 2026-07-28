package githubscan

import (
	"context"
	"fmt"
	"strings"
	"sync"
)

type fixtureRunner struct {
	mutex     sync.Mutex
	responses map[string][]byte
	failures  map[string]error
	calls     []string
}

func (r *fixtureRunner) Run(_ context.Context, _ string, name string, args ...string) ([]byte, error) {
	command := strings.Join(append([]string{name}, args...), " ")
	r.mutex.Lock()
	defer r.mutex.Unlock()
	for prefix, failure := range r.failures {
		if strings.HasPrefix(command, prefix) {
			r.calls = append(r.calls, command)
			return nil, failure
		}
	}
	for prefix, response := range r.responses {
		if strings.HasPrefix(command, prefix) {
			r.calls = append(r.calls, command)
			return append([]byte(nil), response...), nil
		}
	}
	return nil, fmt.Errorf("unexpected command: %s", command)
}

func (r *fixtureRunner) count(prefix string) int {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	count := 0
	for _, call := range r.calls {
		if strings.HasPrefix(call, prefix) {
			count++
		}
	}
	return count
}
