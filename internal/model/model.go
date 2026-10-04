package model

type ScanError struct {
	Repository     string `json:"repository,omitempty"`
	RepositoryPath string `json:"repository_path,omitempty"`
	Stage          string `json:"stage"`
	Message        string `json:"message"`
	Code           string `json:"code,omitempty"`
	WorktreePath   string `json:"worktree_path,omitempty"`
}
