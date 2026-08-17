package agentsession

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"time"
)

func startRolloutWatch(
	ctx context.Context,
	path, sessionID string,
	events chan<- inboundEvent,
	errors chan<- error,
) {
	emit := func() {
		data, err := ReadRolloutTail(path, maxRolloutTail)
		if err != nil {
			return
		}
		event, err := ParseCodexRolloutTail(data, sessionID, time.Now().UTC())
		if err != nil {
			return
		}
		select {
		case events <- inboundEvent{event: event}:
		case <-ctx.Done():
		}
	}
	emit()
	go func() {
		if err := WatchRollout(ctx, path, emit); err != nil && ctx.Err() == nil {
			errors <- err
		}
	}()
}

func watchPendingClosure(ctx context.Context, requestID string, connection net.Conn, output chan<- pendingClosure) {
	buffer := make([]byte, 1)
	_, _ = connection.Read(buffer)
	select {
	case output <- pendingClosure{requestID: requestID, conn: connection}:
	case <-ctx.Done():
	}
}

func environmentMap() map[string]string {
	result := make(map[string]string)
	for _, entry := range os.Environ() {
		for index := range entry {
			if entry[index] == '=' {
				result[entry[:index]] = entry[index+1:]
				break
			}
		}
	}
	return result
}

func snapshotRouting(snapshot Snapshot, id string) Routing {
	for _, session := range snapshot.Sessions {
		if session.ID == id {
			return session.Routing
		}
	}
	return Routing{}
}

func snapshotHasAction(snapshot Snapshot, id, requestID string) bool {
	for _, session := range snapshot.Sessions {
		if session.ID == id && session.Action != nil && session.Action.RequestID == requestID {
			return true
		}
	}
	return false
}

func loadRoutingMap(options ServiceOptions, errOut io.Writer) map[string]RoutingRecord {
	result := make(map[string]RoutingRecord)
	path, err := RoutingPath(serviceEnvironment(options), options.Home)
	if err != nil {
		return result
	}
	records, err := LoadRouting(path, options.Now())
	if err != nil {
		fmt.Fprintf(errOut, "agent routing unavailable: %v\n", err)
		return result
	}
	for _, record := range records {
		result[Identity(record.Provider, record.SessionID)] = record
	}
	return result
}

func saveRoutingMap(options ServiceOptions, values map[string]RoutingRecord, errOut io.Writer) {
	path, err := RoutingPath(serviceEnvironment(options), options.Home)
	if err != nil {
		return
	}
	records := make([]RoutingRecord, 0, len(values))
	for _, record := range values {
		records = append(records, record)
	}
	if err := SaveRouting(path, records, options.Now()); err != nil {
		fmt.Fprintf(errOut, "agent routing save unavailable: %v\n", err)
	}
}

func serviceEnvironment(options ServiceOptions) map[string]string {
	if options.Environment != nil {
		return options.Environment
	}
	return environmentMap()
}
