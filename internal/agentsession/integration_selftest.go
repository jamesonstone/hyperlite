package agentsession

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"net"
	"time"
)

type selfTestResult struct {
	profile string
	request string
	err     error
}

func runIntegrationSelfTest(ctx context.Context, socketPath string, request ControlRequest) error {
	profile, ok := ProfileByID(request.Profile)
	if !ok {
		return errors.New("unknown integration profile")
	}
	dialCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	connection, err := (&net.Dialer{}).DialContext(dialCtx, "unix", socketPath)
	if err != nil {
		return errors.New("self-test bridge unavailable")
	}
	defer func() { _ = connection.Close() }()
	_ = connection.SetDeadline(time.Now().Add(2 * time.Second))
	event := Event{
		Schema: EventSchema, Provider: profile.Provider, Profile: profile.ID,
		SessionID: "hyperlite-self-test-" + request.RequestID, Event: "integration_self_test",
		Phase: PhaseProcessing, Source: SourceHook, OccurredAt: time.Now().UTC(),
		Synthetic: true, TestID: request.RequestID, ReasonCode: "integration_self_test",
	}
	if err := json.NewEncoder(connection).Encode(event); err != nil {
		return errors.New("self-test bridge write failed")
	}
	var acknowledgement HookDecision
	if err := json.NewDecoder(bufio.NewReader(connection)).Decode(&acknowledgement); err != nil {
		return errors.New("self-test acknowledgement missing")
	}
	return nil
}
