//go:build !darwin

package agentsession

import "context"

func WatchRollout(ctx context.Context, path string, changed func()) error {
	<-ctx.Done()
	return nil
}
