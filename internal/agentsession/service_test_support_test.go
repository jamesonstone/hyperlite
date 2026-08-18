package agentsession

import "encoding/json"

func decodeAgentSnapshot(decoder *json.Decoder, snapshot *Snapshot) error {
	for {
		var raw json.RawMessage
		if err := decoder.Decode(&raw); err != nil {
			return err
		}
		var envelope struct {
			Schema string `json:"schema"`
		}
		if json.Unmarshal(raw, &envelope) != nil || envelope.Schema != SnapshotSchema {
			continue
		}
		return json.Unmarshal(raw, snapshot)
	}
}
