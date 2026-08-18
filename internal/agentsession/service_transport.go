package agentsession

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"time"
)

func acceptEvents(ctx context.Context, listener net.Listener, output chan<- inboundEvent, errors chan<- error) {
	slots := make(chan struct{}, 64)
	for {
		connection, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				sendReadError(ctx, errors, err)
				return
			}
		}
		select {
		case slots <- struct{}{}:
			go func() {
				defer func() { <-slots }()
				decodeEvent(ctx, connection, output)
			}()
		default:
			_ = connection.Close()
		}
	}
}

func decodeEvent(ctx context.Context, connection net.Conn, output chan<- inboundEvent) {
	_ = connection.SetReadDeadline(time.Now().Add(2 * time.Second))
	var event Event
	decoder := json.NewDecoder(io.LimitReader(connection, MaxHookPayload+1))
	if err := decoder.Decode(&event); err != nil || event.Schema != EventSchema {
		_ = connection.Close()
		return
	}
	_ = connection.SetDeadline(time.Time{})
	select {
	case output <- inboundEvent{event: event, conn: connection}:
	case <-ctx.Done():
		_ = connection.Close()
	}
}
