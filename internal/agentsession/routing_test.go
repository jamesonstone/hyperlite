package agentsession

import (
	"testing"
	"time"
)

func TestPruneRoutingKeepsNewestDuplicate(t *testing.T) {
	now := timeForTest()
	records := []RoutingRecord{
		{Provider: "codex", SessionID: "thread", LastSeen: now.Add(-time.Hour), Routing: Routing{Terminal: "old"}},
		{Provider: "codex", SessionID: "thread", LastSeen: now, Routing: Routing{Terminal: "new"}},
	}
	pruned := pruneRouting(records, now)
	if len(pruned) != 1 || pruned[0].Routing.Terminal != "new" || !pruned[0].LastSeen.Equal(now) {
		t.Fatalf("newest routing record was not retained: %#v", pruned)
	}
}
