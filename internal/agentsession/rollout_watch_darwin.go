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
	defer func() { _ = file.Close() }()
	queue, err := syscall.Kqueue()
	if err != nil {
		return err
	}
	const cancelEventID = 1
	vnodeEvent := syscall.Kevent_t{
		Ident: uint64(file.Fd()), Filter: syscall.EVFILT_VNODE,
		Flags:  syscall.EV_ADD | syscall.EV_CLEAR,
		Fflags: syscall.NOTE_WRITE | syscall.NOTE_EXTEND | syscall.NOTE_RENAME | syscall.NOTE_DELETE,
	}
	cancelEvent := syscall.Kevent_t{
		Ident: cancelEventID, Filter: syscall.EVFILT_USER,
		Flags: syscall.EV_ADD | syscall.EV_CLEAR,
	}
	if _, err := syscall.Kevent(queue, []syscall.Kevent_t{vnodeEvent, cancelEvent}, nil, nil); err != nil {
		_ = syscall.Close(queue)
		return err
	}
	stopWake := make(chan struct{})
	wakeDone := make(chan struct{})
	go func() {
		defer close(wakeDone)
		select {
		case <-ctx.Done():
			trigger := syscall.Kevent_t{
				Ident: cancelEventID, Filter: syscall.EVFILT_USER,
				Fflags: syscall.NOTE_TRIGGER,
			}
			_, _ = syscall.Kevent(queue, []syscall.Kevent_t{trigger}, nil, nil)
		case <-stopWake:
		}
	}()
	defer func() {
		close(stopWake)
		<-wakeDone
		_ = syscall.Close(queue)
	}()
	for {
		events := make([]syscall.Kevent_t, 2)
		count, waitErr := syscall.Kevent(queue, nil, events, nil)
		if waitErr != nil {
			if ctx.Err() != nil {
				return nil
			}
			if waitErr == syscall.EINTR {
				continue
			}
			return waitErr
		}
		for _, event := range events[:count] {
			if event.Filter == syscall.EVFILT_USER {
				return nil
			}
			changed()
			if event.Fflags&(syscall.NOTE_RENAME|syscall.NOTE_DELETE) != 0 {
				return nil
			}
		}
	}
}
