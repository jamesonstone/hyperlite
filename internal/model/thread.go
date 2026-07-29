package model

import "time"

const ThreadScanSchemaVersion = 2

type ThreadPhase string

const (
	ThreadShaping          ThreadPhase = "shaping"
	ThreadPlanned          ThreadPhase = "planned"
	ThreadImplementing     ThreadPhase = "implementing"
	ThreadReviewing        ThreadPhase = "reviewing"
	ThreadOperationalizing ThreadPhase = "operationalizing"
	ThreadReflecting       ThreadPhase = "reflecting"
	ThreadComplete         ThreadPhase = "complete"
)

type ArtifactKind string

const (
	ArtifactIssue          ArtifactKind = "issue"
	ArtifactSpec           ArtifactKind = "spec"
	ArtifactPlan           ArtifactKind = "plan"
	ArtifactPullRequest    ArtifactKind = "pull_request"
	ArtifactReview         ArtifactKind = "review"
	ArtifactBranch         ArtifactKind = "branch"
	ArtifactWorktree       ArtifactKind = "worktree"
	ArtifactInfrastructure ArtifactKind = "infrastructure"
)

type RelationKind string

const (
	RelationDependsOn   RelationKind = "depends_on"
	RelationMustPrecede RelationKind = "must_precede"
	RelationAffects     RelationKind = "affects"
	RelationSupports    RelationKind = "supports"
)

type EvidenceBasis string

const (
	BasisExplicit   EvidenceBasis = "explicit"
	BasisExtracted  EvidenceBasis = "extracted"
	BasisHypothesis EvidenceBasis = "hypothesis"
)

type AttentionKind string

const (
	AttentionDecide    AttentionKind = "decide"
	AttentionKnow      AttentionKind = "know"
	AttentionGuard     AttentionKind = "guard"
	AttentionReconcile AttentionKind = "reconcile"
	AttentionUncertain AttentionKind = "uncertain"
)

type EvidenceRef struct {
	ID         string    `json:"id"`
	Source     string    `json:"source"`
	Repository string    `json:"repository"`
	Kind       string    `json:"kind"`
	Title      string    `json:"title"`
	URL        string    `json:"url,omitempty"`
	Path       string    `json:"path,omitempty"`
	Excerpt    string    `json:"excerpt,omitempty"`
	UpdatedAt  time.Time `json:"updated_at,omitempty"`
	Freshness  string    `json:"freshness"`
}

type ThreadArtifact struct {
	ID         string       `json:"id"`
	Kind       ArtifactKind `json:"kind"`
	Repository string       `json:"repository"`
	Title      string       `json:"title"`
	State      string       `json:"state"`
	URL        string       `json:"url,omitempty"`
	Path       string       `json:"path,omitempty"`
	EvidenceID string       `json:"evidence_id"`
	UpdatedAt  time.Time    `json:"updated_at,omitempty"`
	Freshness  string       `json:"freshness"`
}

type ThreadRelation struct {
	Kind           RelationKind  `json:"kind"`
	TargetThreadID string        `json:"target_thread_id,omitempty"`
	Target         string        `json:"target"`
	Basis          EvidenceBasis `json:"basis"`
	Confidence     float64       `json:"confidence"`
	EvidenceIDs    []string      `json:"evidence_ids"`
}

type ThreadObligation struct {
	ID          string        `json:"id"`
	Summary     string        `json:"summary"`
	Satisfied   bool          `json:"satisfied"`
	Basis       EvidenceBasis `json:"basis"`
	Confidence  float64       `json:"confidence"`
	EvidenceIDs []string      `json:"evidence_ids"`
}

type ThreadImplication struct {
	Summary     string        `json:"summary"`
	Category    string        `json:"category"`
	Basis       EvidenceBasis `json:"basis"`
	Confidence  float64       `json:"confidence"`
	EvidenceIDs []string      `json:"evidence_ids"`
}

type AttentionMoment struct {
	ID          string        `json:"id"`
	Kind        AttentionKind `json:"kind"`
	Summary     string        `json:"summary"`
	Action      string        `json:"action"`
	Why         string        `json:"why"`
	Consequence string        `json:"consequence"`
	ValidWhile  string        `json:"valid_while"`
	Revision    string        `json:"revision"`
	EvidenceIDs []string      `json:"evidence_ids"`
	CreatedAt   time.Time     `json:"created_at"`
	Seen        bool          `json:"seen"`
}

type Thread struct {
	ID                     string              `json:"id"`
	Aliases                []string            `json:"aliases"`
	Title                  string              `json:"title"`
	Goal                   string              `json:"goal"`
	Rationale              string              `json:"rationale"`
	Phase                  ThreadPhase         `json:"phase"`
	Active                 bool                `json:"active"`
	Repositories           []string            `json:"repositories"`
	Artifacts              []ThreadArtifact    `json:"artifacts"`
	Dependencies           []ThreadRelation    `json:"dependencies"`
	Implications           []ThreadImplication `json:"implications"`
	Obligations            []ThreadObligation  `json:"obligations"`
	Evidence               []EvidenceRef       `json:"evidence"`
	Attention              []AttentionMoment   `json:"attention"`
	LatestMaterialRevision string              `json:"latest_material_revision"`
	WhyNow                 string              `json:"why_now"`
	Confidence             float64             `json:"confidence"`
	InferenceStatus        string              `json:"inference_status"`
	Note                   string              `json:"note,omitempty"`
	UpdatedAt              time.Time           `json:"updated_at"`
}

type ThreadScanSummary struct {
	Projects  int `json:"projects"`
	Threads   int `json:"threads"`
	Attention int `json:"attention"`
	InFlight  int `json:"in_flight"`
	Completed int `json:"completed"`
	Errors    int `json:"errors"`
	Warnings  int `json:"warnings"`
}

type ThreadScan struct {
	SchemaVersion                int               `json:"schema_version"`
	GeneratedAt                  time.Time         `json:"generated_at"`
	RemoteObservedAt             *time.Time        `json:"remote_observed_at,omitempty"`
	RemoteRefreshIntervalSeconds int64             `json:"remote_refresh_interval_seconds"`
	Summary                      ThreadScanSummary `json:"summary"`
	Threads                      []Thread          `json:"threads"`
	Errors                       []ScanError       `json:"errors"`
	Warnings                     []ScanError       `json:"warnings"`
}

type InferenceClaim struct {
	Text        string   `json:"text"`
	EvidenceIDs []string `json:"evidence_ids"`
}

type InferenceRelation struct {
	Kind           RelationKind  `json:"kind"`
	TargetThreadID string        `json:"target_thread_id"`
	Target         string        `json:"target"`
	Basis          EvidenceBasis `json:"basis"`
	Confidence     float64       `json:"confidence"`
	EvidenceIDs    []string      `json:"evidence_ids"`
}

type InferenceThread struct {
	ThreadID          string              `json:"thread_id"`
	Goal              InferenceClaim      `json:"goal"`
	Rationale         InferenceClaim      `json:"rationale"`
	Implications      []ThreadImplication `json:"implications"`
	Obligations       []ThreadObligation  `json:"obligations"`
	Relations         []InferenceRelation `json:"relations"`
	ReviewSignificant bool                `json:"review_significant"`
	ReviewSummary     InferenceClaim      `json:"review_summary"`
	Confidence        float64             `json:"confidence"`
}
