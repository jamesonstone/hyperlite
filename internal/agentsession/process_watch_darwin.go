//go:build darwin

package agentsession

import (
	"context"
	"errors"
	"fmt"

	"golang.org/x/sys/unix"
)

func ProcessStartToken(pid int) (string, error) {
	info, err := unix.SysctlKinfoProc("kern.proc.pid", pid)
	if err != nil || info == nil || int(info.Proc.P_pid) != pid {
		return "", errors.New("process identity is unavailable")
	}
	return fmt.Sprintf("%d:%d", info.Proc.P_starttime.Sec, info.Proc.P_starttime.Usec), nil
}

func WatchExactProcessExit(ctx context.Context, pid int, token string) error {
	observed, err := ProcessStartToken(pid)
	if err != nil || observed != token {
		return errors.New("process start token does not match")
	}
	queue, err := unix.Kqueue()
	if err != nil {
		return err
	}
	const cancelEventID = 1
	processEvent := unix.Kevent_t{
		Ident: uint64(pid), Filter: unix.EVFILT_PROC,
		Flags: unix.EV_ADD | unix.EV_ONESHOT, Fflags: unix.NOTE_EXIT,
	}
	cancelEvent := unix.Kevent_t{
		Ident: cancelEventID, Filter: unix.EVFILT_USER,
		Flags: unix.EV_ADD | unix.EV_CLEAR,
	}
	if _, err := unix.Kevent(queue, []unix.Kevent_t{processEvent, cancelEvent}, nil, nil); err != nil {
		_ = unix.Close(queue)
		if errors.Is(err, unix.ESRCH) {
			return nil
		}
		return err
	}
	stopWake := make(chan struct{})
	wakeDone := make(chan struct{})
	go func() {
		defer close(wakeDone)
		select {
		case <-ctx.Done():
			trigger := unix.Kevent_t{Ident: cancelEventID, Filter: unix.EVFILT_USER, Fflags: unix.NOTE_TRIGGER}
			_, _ = unix.Kevent(queue, []unix.Kevent_t{trigger}, nil, nil)
		case <-stopWake:
		}
	}()
	defer func() {
		close(stopWake)
		<-wakeDone
		_ = unix.Close(queue)
	}()
	for {
		events := make([]unix.Kevent_t, 2)
		count, waitErr := unix.Kevent(queue, nil, events, nil)
		if waitErr == unix.EINTR {
			continue
		}
		if waitErr != nil {
			return waitErr
		}
		for _, event := range events[:count] {
			if event.Filter == unix.EVFILT_USER {
				return ctx.Err()
			}
			if event.Filter == unix.EVFILT_PROC && event.Fflags&unix.NOTE_EXIT != 0 {
				return nil
			}
		}
	}
}
