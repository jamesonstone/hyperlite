package agentsession

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

type blockingOwnerInput struct {
	closed chan struct{}
	once   sync.Once
}

func (r *blockingOwnerInput) Read(_ []byte) (int, error) {
	<-r.closed
	return 0, os.ErrClosed
}

func (r *blockingOwnerInput) Close() error {
	r.once.Do(func() { close(r.closed) })
	return nil
}

type failingOwnerInput struct{ err error }

func (r failingOwnerInput) Read(_ []byte) (int, error) { return 0, r.err }

func TestServiceCancellationClosesOwnedInput(t *testing.T) {
	runtimeDir := shortRuntimeDir(t, "cancel-input")
	input := &blockingOwnerInput{closed: make(chan struct{})}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- RunService(ctx, input, io.Discard, io.Discard, ServiceOptions{
			SocketPath: filepath.Join(runtimeDir, "agent.sock"), Home: t.TempDir(), DisableCodex: true,
		})
	}()
	waitForSocket(t, filepath.Join(runtimeDir, "agent.sock"))
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("service cancellation did not unblock owned input")
	}
	select {
	case <-input.closed:
	default:
		t.Fatal("service did not close its owned input")
	}
}

func TestServiceTerminatesAfterOwnerInputError(t *testing.T) {
	runtimeDir := shortRuntimeDir(t, "owner-error")
	want := errors.New("fixture read failure")
	err := RunService(context.Background(), failingOwnerInput{err: want}, io.Discard, io.Discard, ServiceOptions{
		SocketPath: filepath.Join(runtimeDir, "agent.sock"), Home: t.TempDir(), DisableCodex: true,
	})
	var ownerErr ownerInputError
	if !errors.As(err, &ownerErr) || !errors.Is(err, want) {
		t.Fatalf("owner input error = %v", err)
	}
}

func shortRuntimeDir(t *testing.T, name string) string {
	t.Helper()
	directory := filepath.Join("/tmp", name+"-"+time.Now().Format("150405.000000"))
	if err := os.Mkdir(directory, 0o700); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	return directory
}
