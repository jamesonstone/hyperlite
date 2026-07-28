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
	if failure, found := longestPrefixValue(command, r.failures); found {
		r.calls = append(r.calls, command)
		return nil, failure
	}
	if response, found := longestPrefixValue(command, r.responses); found {
		r.calls = append(r.calls, command)
		return append([]byte(nil), response...), nil
	}
	return nil, fmt.Errorf("unexpected command: %s", command)
}

func longestPrefixValue[T any](command string, values map[string]T) (T, bool) {
	var match string
	for prefix := range values {
		if strings.HasPrefix(command, prefix) && len(prefix) > len(match) {
			match = prefix
		}
	}
	value, found := values[match]
	return value, found
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
