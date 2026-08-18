package agentsession

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
)

type serviceInput struct {
	action  *ActionRequest
	control *ControlRequest
}

type ownerInputError struct{ err error }

func (e ownerInputError) Error() string { return "agent session owner input failed" }
func (e ownerInputError) Unwrap() error { return e.err }

func closeOwnerInputOnCancel(ctx context.Context, input io.Reader) {
	closer, ok := input.(io.ReadCloser)
	if !ok {
		return
	}
	go func() {
		<-ctx.Done()
		_ = closer.Close()
	}()
}

func readServiceInput(ctx context.Context, input io.Reader, output chan<- serviceInput, errors chan<- error) {
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), MaxHookPayload)
	for scanner.Scan() {
		var envelope struct {
			Schema string `json:"schema"`
		}
		if json.Unmarshal(scanner.Bytes(), &envelope) != nil {
			continue
		}
		var value serviceInput
		switch envelope.Schema {
		case ActionSchema, ActionSchemaV1:
			var request ActionRequest
			if json.Unmarshal(scanner.Bytes(), &request) != nil {
				continue
			}
			value.action = &request
		case ControlSchema:
			var request ControlRequest
			if json.Unmarshal(scanner.Bytes(), &request) != nil || !request.Valid() {
				continue
			}
			value.control = &request
		default:
			continue
		}
		select {
		case output <- value:
		case <-ctx.Done():
			return
		}
	}
	if err := scanner.Err(); err != nil {
		sendReadError(ctx, errors, ownerInputError{err: err})
	} else {
		sendReadError(ctx, errors, io.EOF)
	}
}
