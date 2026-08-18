//go:build !darwin

package agentsession

import (
	"context"
	"errors"
)

func ProcessStartToken(_ int) (string, error) {
	return "", errors.New("exact process observation is unsupported")
}

func WatchExactProcessExit(ctx context.Context, _ int, _ string) error {
	<-ctx.Done()
	return ctx.Err()
}
