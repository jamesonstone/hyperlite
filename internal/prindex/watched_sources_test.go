package prindex

import (
	"context"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestScannerSkipsIgnoredProjectsAndHonorsRefreshOnly(t *testing.T) {
	now := time.Date(2026, 10, 4, 12, 0, 0, 0, time.UTC)
	watched := config.Source{Path: "/repo/watched"}
	other := config.Source{Path: "/repo/other"}
	ignored := config.Source{Path: "/repo/ignored", Ignored: true}
	repositories := []config.Repository{
		{Name: "watched", Path: watched.Path, GitHub: "owner/watched"},
		{Name: "other", Path: other.Path, GitHub: "owner/other"},
		{Name: "ignored", Path: ignored.Path, GitHub: "owner/ignored"},
	}
	store := &memoryCacheStore{state: cacheState{
		Version: cacheVersion, Projects: map[string]string{},
		Repositories: map[string]cacheEntry{"owner/ignored": {
			Repository: "owner/ignored", ObservedAt: now,
			PullRequests: []model.ProjectPullRequest{{ID: "owner/ignored#1", Number: 1}},
		}},
	}}
	client := &fakePullRequestClient{results: map[string]RepositoryResult{}}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{Repositories: repositories}},
		Client:    client, Store: store, Now: func() time.Time { return now },
	}
	cfg := config.Config{Projects: []config.Source{watched, other, ignored}}
	result, err := scanner.Scan(context.Background(), cfg, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	if len(client.repositories) != 1 || len(client.repositories[0]) != 2 {
		t.Fatalf("queried = %#v", client.repositories)
	}
	for _, repository := range client.repositories[0] {
		if repository.GitHub == "owner/ignored" {
			t.Fatal("an ignored project must never be queried")
		}
	}
	last := result.Projects[2]
	if !last.Ignored || len(last.PullRequests) != 0 || last.Workflows != nil {
		t.Fatalf("ignored projection = %#v", last)
	}

	cfg.RefreshOnly = []string{other.Path}
	if _, err := scanner.Scan(context.Background(), cfg, RefreshForce); err != nil {
		t.Fatal(err)
	}
	if got := client.repositories[1]; len(got) != 1 || got[0].GitHub != "owner/other" {
		t.Fatalf("refresh-only queried = %#v", got)
	}
}
