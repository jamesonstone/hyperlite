package agentsession

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
)

func reconcileRolloutSeed(event, seed Event) (Event, bool) {
	if event.SessionID != seed.SessionID {
		return Event{}, false
	}
	event.ParentID = firstNonempty(event.ParentID, seed.ParentID)
	event.Title = firstNonempty(event.Title, seed.Title)
	event.WorkspacePath = firstNonempty(event.WorkspacePath, seed.WorkspacePath)
	event.Routing = mergeRouting(seed.Routing, event.Routing, event.WorkspacePath)
	return event, true
}

func sendReadError(ctx context.Context, output chan<- error, err error) {
	select {
	case output <- err:
	case <-ctx.Done():
	}
}

func watchPendingClosure(ctx context.Context, key string, connection net.Conn, output chan<- pendingClosure) {
	buffer := make([]byte, 1)
	_, _ = connection.Read(buffer)
	select {
	case output <- pendingClosure{key: key, conn: connection}:
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
		if session.ID == id {
			_, ok := actionByRequest(session.Actions, requestID)
			return ok
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
		_, _ = fmt.Fprintln(errOut, "agent routing unavailable: routing_read_error")
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
		_, _ = fmt.Fprintln(errOut, "agent routing save unavailable: routing_write_error")
	}
}

func closePending(values map[string]pendingResponse) {
	for _, value := range values {
		_ = value.conn.Close()
	}
}

func serviceEnvironment(options ServiceOptions) map[string]string {
	if options.Environment != nil {
		return options.Environment
	}
	return environmentMap()
}
