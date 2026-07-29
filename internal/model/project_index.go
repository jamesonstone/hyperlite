package model

// ProjectIndexEntry is a configuration-backed spatial reference. It is
// intentionally independent of inferred thread liveness and attention.
type ProjectIndexEntry struct {
	ID         string        `json:"id"`
	Name       string        `json:"name"`
	Path       string        `json:"path"`
	Repository string        `json:"repository,omitempty"`
	Lanes      []ProjectLane `json:"lanes"`
}

// ProjectLane identifies one real local checkout registered with Git. The
// configured checkout remains present even when repository inspection fails.
type ProjectLane struct {
	ID       string `json:"id"`
	Branch   string `json:"branch,omitempty"`
	Path     string `json:"path"`
	Primary  bool   `json:"primary"`
	Detached bool   `json:"detached"`
}
