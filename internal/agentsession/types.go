package agentsession

import "time"

const (
	SnapshotSchemaV1   = "agent_session_snapshot.v1"
	SnapshotSchema     = "agent_session_snapshot.v2"
	ActionSchemaV1     = "agent_session_action.v1"
	ActionSchema       = "agent_session_action.v2"
	ActionResultSchema = "agent_session_action_result.v1"
	IntegrationSchema  = "agent_integration_status.v1"
	EventSchema        = "agent_session_event.v1"
	maxMessages        = 6
	maxPendingActions  = 8
	maxSessions        = 100
	maxMessageRunes    = 2_000
	maxResultRunes     = 8_000
	maxActionRunes     = 8_000
)

type Phase string

const (
	PhaseStarting        Phase = "starting"
	PhaseProcessing      Phase = "processing"
	PhaseWaitingApproval Phase = "waiting_for_approval"
	PhaseWaitingInput    Phase = "waiting_for_input"
	PhaseIdle            Phase = "idle"
	PhaseCompleted       Phase = "completed"
	PhaseError           Phase = "error"
	PhaseEnded           Phase = "ended"
)

func (p Phase) NeedsAttention() bool {
	return p == PhaseWaitingApproval || p == PhaseWaitingInput
}

func (p Phase) Active() bool {
	return p == PhaseStarting || p == PhaseProcessing
}

type Source string

const (
	SourceHook      Source = "hook"
	SourceAppServer Source = "app_server"
	SourceRollout   Source = "rollout"
	SourceStored    Source = "stored"
)

func (s Source) Authority() int {
	switch s {
	case SourceHook:
		return 4
	case SourceAppServer:
		return 3
	case SourceRollout:
		return 2
	default:
		return 1
	}
}

type Message struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

type PendingAction struct {
	RequestID       string            `json:"request_id"`
	Kind            string            `json:"kind"`
	Title           string            `json:"title"`
	Context         string            `json:"context"`
	Arguments       map[string]string `json:"arguments,omitempty"`
	CompleteContext bool              `json:"complete_context"`
	CanAllowOnce    bool              `json:"can_allow_once"`
	CanDeny         bool              `json:"can_deny"`
	CanAnswer       bool              `json:"can_answer"`
	CanAllowSession bool              `json:"can_allow_session"`
	CanRevoke       bool              `json:"can_revoke"`
	Revision        uint64            `json:"revision"`
}

type Routing struct {
	BundleID      string `json:"bundle_id,omitempty"`
	Terminal      string `json:"terminal,omitempty"`
	TerminalID    string `json:"terminal_id,omitempty"`
	TmuxSession   string `json:"tmux_session,omitempty"`
	TmuxPane      string `json:"tmux_pane,omitempty"`
	WorkspacePath string `json:"workspace_path,omitempty"`
}

type Session struct {
	ID           string          `json:"id"`
	Provider     string          `json:"provider"`
	Profile      string          `json:"profile"`
	SessionID    string          `json:"session_id"`
	ParentID     string          `json:"parent_id,omitempty"`
	Project      string          `json:"project"`
	Title        string          `json:"title"`
	Phase        Phase           `json:"phase"`
	Source       Source          `json:"source"`
	Revision     uint64          `json:"revision"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
	Messages     []Message       `json:"messages"`
	LatestResult string          `json:"latest_result,omitempty"`
	Actions      []PendingAction `json:"actions"`
	Routing      Routing         `json:"routing"`
	OpenInClient bool            `json:"open_in_client"`
	Synthetic    bool            `json:"synthetic,omitempty"`
}

func (s Session) NeedsAttention() bool {
	return len(s.Actions) > 0 || s.Phase.NeedsAttention()
}

func (s Session) CurrentAction() *PendingAction {
	if len(s.Actions) == 0 {
		return nil
	}
	return &s.Actions[0]
}

type Snapshot struct {
	Schema       string              `json:"schema"`
	Generation   uint64              `json:"generation"`
	GeneratedAt  time.Time           `json:"generated_at"`
	Sessions     []Session           `json:"sessions"`
	Integrations []IntegrationStatus `json:"integrations"`
}

type Event struct {
	Schema             string         `json:"schema,omitempty"`
	Provider           string         `json:"provider"`
	Profile            string         `json:"profile"`
	SessionID          string         `json:"session_id"`
	ParentID           string         `json:"parent_id,omitempty"`
	Event              string         `json:"event"`
	Phase              Phase          `json:"phase,omitempty"`
	Source             Source         `json:"source"`
	OccurredAt         time.Time      `json:"occurred_at,omitempty"`
	WorkspacePath      string         `json:"workspace_path,omitempty"`
	Title              string         `json:"title,omitempty"`
	MessageRole        string         `json:"message_role,omitempty"`
	Message            string         `json:"message,omitempty"`
	Messages           []Message      `json:"messages,omitempty"`
	LatestResult       string         `json:"latest_result,omitempty"`
	RequestID          string         `json:"request_id,omitempty"`
	ActionKind         string         `json:"action_kind,omitempty"`
	ActionTitle        string         `json:"action_title,omitempty"`
	ActionContext      string         `json:"action_context,omitempty"`
	Arguments          map[string]any `json:"arguments,omitempty"`
	CompleteContext    bool           `json:"complete_context,omitempty"`
	ExpectsResponse    bool           `json:"expects_response,omitempty"`
	Routing            Routing        `json:"routing,omitempty"`
	RolloutPath        string         `json:"rollout_path,omitempty"`
	AuxiliaryKind      string         `json:"auxiliary_kind,omitempty"`
	HasPrompt          bool           `json:"has_prompt,omitempty"`
	ActiveTool         bool           `json:"active_tool,omitempty"`
	ProcessID          int            `json:"process_id,omitempty"`
	ProcessStart       string         `json:"process_start_token,omitempty"`
	Synthetic          bool           `json:"synthetic,omitempty"`
	TestID             string         `json:"test_id,omitempty"`
	ReasonCode         string         `json:"reason_code,omitempty"`
	rolloutHint        bool
	rolloutCaughtUp    bool
	visibilityReleased bool
}

type ActionRequest struct {
	Schema    string              `json:"schema"`
	Provider  string              `json:"provider,omitempty"`
	SessionID string              `json:"session_id"`
	RequestID string              `json:"request_id"`
	Revision  uint64              `json:"revision"`
	Action    string              `json:"action"`
	Answers   map[string][]string `json:"answers,omitempty"`
}

type ActionResult struct {
	Schema    string `json:"schema"`
	SessionID string `json:"session_id"`
	RequestID string `json:"request_id"`
	Action    string `json:"action"`
	Status    string `json:"status"`
	Message   string `json:"message,omitempty"`
}

type IntegrationStatus struct {
	Schema     string `json:"schema,omitempty"`
	ID         string `json:"id"`
	Name       string `json:"name"`
	Provider   string `json:"provider"`
	Detected   bool   `json:"detected"`
	Enabled    bool   `json:"enabled"`
	ActionMode string `json:"action_mode"`
	Target     string `json:"target,omitempty"`
	Message    string `json:"message,omitempty"`
}
