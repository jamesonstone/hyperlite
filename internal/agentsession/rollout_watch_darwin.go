//go:build darwin

package agentsession

import (
	"context"
	"os"
	"syscall"
)

func WatchRollout(ctx context.Context, path string, changed func()) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	queue, err := syscall.Kqueue()
	if err != nil {
		return err
	}
	defer syscall.Close(queue)
	event := syscall.Kevent_t{
		Ident: uint64(file.Fd()), Filter: syscall.EVFILT_VNODE,
		Flags:  syscall.EV_ADD | syscall.EV_CLEAR,
		Fflags: syscall.NOTE_WRITE | syscall.NOTE_EXTEND | syscall.NOTE_RENAME | syscall.NOTE_DELETE,
	}
	if _, err := syscall.Kevent(queue, []syscall.Kevent_t{event}, nil, nil); err != nil {
		return err
	}
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			_ = syscall.Close(queue)
		case <-done:
		}
	}()
	defer close(done)
	for {
		events := make([]syscall.Kevent_t, 1)
		count, waitErr := syscall.Kevent(queue, nil, events, nil)
		if ctx.Err() != nil {
			return nil
		}
		if waitErr != nil {
			return waitErr
		}
		if count == 0 {
			continue
		}
		changed()
		if events[0].Fflags&(syscall.NOTE_RENAME|syscall.NOTE_DELETE) != 0 {
			return nil
		}
	}
}
