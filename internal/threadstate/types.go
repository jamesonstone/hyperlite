package threadstate

import (
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

const Version = 1

type MaterialSignature struct {
	Goal         string            `json:"goal"`
	Rationale    string            `json:"rationale"`
	Phase        model.ThreadPhase `json:"phase"`
	Dependencies string            `json:"dependencies"`
	Implications string            `json:"implications"`
	Obligations  string            `json:"obligations"`
	Review       string            `json:"review"`
}

type ThreadRecord struct {
	ID           string                  `json:"id"`
	Aliases      []string                `json:"aliases"`
	Revision     string                  `json:"revision"`
	SeenRevision string                  `json:"seen_revision,omitempty"`
	Note         string                  `json:"note,omitempty"`
	Signature    MaterialSignature       `json:"signature"`
	Moments      []model.AttentionMoment `json:"moments"`
	Snapshot     model.Thread            `json:"snapshot"`
	Missing      bool                    `json:"missing,omitempty"`
	UpdatedAt    time.Time               `json:"updated_at"`
}

type RemoteCache struct {
	ObservedAt time.Time            `json:"observed_at"`
	Evidence   model.RemoteEvidence `json:"evidence"`
}

type InferenceRecord struct {
	ThreadID  string                `json:"thread_id"`
	Digest    string                `json:"digest"`
	Inference model.InferenceThread `json:"inference"`
	UpdatedAt time.Time             `json:"updated_at"`
}

type State struct {
	Version    int                    `json:"version"`
	Remote     map[string]RemoteCache `json:"remote"`
	Threads    []ThreadRecord         `json:"threads"`
	Inferences []InferenceRecord      `json:"inferences"`
	UpdatedAt  time.Time              `json:"updated_at"`
}

func Empty() State {
	return State{
		Version: Version, Remote: map[string]RemoteCache{},
		Threads: []ThreadRecord{}, Inferences: []InferenceRecord{},
	}
}
