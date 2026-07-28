package threadbuild

import (
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

var issueURLPattern = regexp.MustCompile(`^https://github\.com/([^/]+/[^/]+)/issues/(\d+)$`)

type Input struct {
	Repository  config.Repository
	Locals      []gitscan.LocalLane
	Remote      model.RemoteEvidence
	Documents   []memoryscan.Document
	RemoteStale bool
	Now         time.Time
}

type accumulator struct {
	thread      model.Thread
	issueNumber int
	hasSpec     bool
	headOIDs    []string
}

func Build(input Input) []model.Thread {
	if input.Now.IsZero() {
		input.Now = time.Now().UTC()
	}
	builders := make(map[string]*accumulator)
	aliases := make(map[string]string)
	for _, document := range input.Documents {
		addDocument(input.Repository, document, builders, aliases)
	}
	for _, issue := range input.Remote.Issues {
		addIssue(input.Repository, issue, input.RemoteStale, builders, aliases, input.Now)
	}
	for _, pullRequest := range input.Remote.PullRequests {
		addPullRequest(input.Repository, pullRequest, input.RemoteStale, builders, aliases, input.Now)
	}
	for _, local := range input.Locals {
		addLocal(input.Repository, local, builders, aliases, input.Now)
	}
	threads := make([]model.Thread, 0, len(builders))
	for _, builder := range builders {
		finalize(&builder.thread, builder.hasSpec, builder.issueNumber, input.Now)
		if builder.thread.Active || recent(builder.thread.UpdatedAt, input.Now, 30*24*time.Hour) {
			threads = append(threads, builder.thread)
		}
	}
	sort.Slice(threads, func(i, j int) bool {
		if threads[i].Active != threads[j].Active {
			return threads[i].Active
		}
		if !threads[i].UpdatedAt.Equal(threads[j].UpdatedAt) {
			return threads[i].UpdatedAt.After(threads[j].UpdatedAt)
		}
		return threads[i].ID < threads[j].ID
	})
	return threads
}

func addDocument(repo config.Repository, document memoryscan.Document, builders map[string]*accumulator, aliases map[string]string) {
	issueNumber := matchingIssueNumber(repo.GitHub, document.IssueURLs, document.IssueNumbers)
	id := fmt.Sprintf("spec:%s:%s", repo.GitHub, document.FeatureID)
	if issueNumber > 0 {
		id = issueID(repo.GitHub, issueNumber)
	}
	builder := ensure(builders, id, repo)
	builder.hasSpec = true
	if issueNumber > 0 {
		builder.issueNumber = issueNumber
	}
	specAlias := fmt.Sprintf("spec:%s:%s", repo.GitHub, document.FeatureID)
	addAliases(builder, aliases, id, append([]string{specAlias}, document.IssueURLs...)...)
	title := document.Title
	if strings.EqualFold(strings.TrimSpace(title), "spec") {
		title = ""
	}
	builder.thread.Title = firstNonEmpty(title, humanize(document.Slug), "Feature "+document.FeatureID)
	builder.thread.Goal = firstParagraph(document.Purpose)
	builder.thread.Rationale = firstParagraph(document.Context)
	builder.thread.Phase = phaseFromDocument(document.Phase)
	evidenceID := specAlias
	excerpt := joinExcerpt(document.Purpose, document.Context, document.Plan, document.Decisions, document.Outcome)
	addEvidence(&builder.thread, model.EvidenceRef{
		ID: evidenceID, Source: "repository_memory", Repository: repo.GitHub,
		Kind: "spec", Title: builder.thread.Title,
		Path:    evidencePath(document.RepositoryRoot, document.Path),
		Excerpt: excerpt, UpdatedAt: document.UpdatedAt, Freshness: "current",
	})
	addArtifact(&builder.thread, model.ThreadArtifact{
		ID: evidenceID, Kind: model.ArtifactSpec, Repository: repo.GitHub,
		Title: builder.thread.Title, State: strings.ToLower(document.Phase),
		Path:       evidencePath(document.RepositoryRoot, document.Path),
		EvidenceID: evidenceID, UpdatedAt: document.UpdatedAt,
		Freshness: "current",
	})
	for _, candidate := range document.Obligations {
		builder.thread.Obligations = append(builder.thread.Obligations, model.ThreadObligation{
			ID: stableID("obligation", evidenceID, candidate.Summary), Summary: candidate.Summary,
			Satisfied: candidate.Satisfied, Basis: model.BasisExtracted, Confidence: 0.8,
			EvidenceIDs: []string{evidenceID},
		})
	}
	for _, candidate := range document.Implications {
		builder.thread.Implications = append(builder.thread.Implications, model.ThreadImplication{
			Summary: candidate.Summary, Category: implicationCategory(candidate.Summary),
			Basis: model.BasisExtracted, Confidence: 0.75, EvidenceIDs: []string{evidenceID},
		})
	}
	for _, reference := range document.References {
		if relation, ok := relationKind(reference.Relation); ok {
			builder.thread.Dependencies = append(builder.thread.Dependencies, model.ThreadRelation{
				Kind: relation, Target: reference.Target, Basis: model.BasisExplicit,
				Confidence: 1, EvidenceIDs: []string{evidenceID},
			})
		}
	}
	documentRoot := firstNonEmpty(document.RepositoryRoot, repo.Path)
	for _, referenced := range document.ReadReferencedDocuments(documentRoot) {
		kind := model.ArtifactPlan
		lower := strings.ToLower(referenced.Path)
		if strings.Contains(lower, "deploy") || strings.Contains(lower, "infrastructure") {
			kind = model.ArtifactInfrastructure
		}
		referenceID := fmt.Sprintf("doc:%s:%s", repo.GitHub, referenced.Path)
		addEvidence(&builder.thread, model.EvidenceRef{
			ID: referenceID, Source: "repository_memory", Repository: repo.GitHub,
			Kind: string(kind), Title: referenced.Title,
			Path:    evidencePath(referenced.RepositoryRoot, referenced.Path),
			Excerpt: referenced.Purpose, UpdatedAt: referenced.UpdatedAt, Freshness: "current",
		})
		addArtifact(&builder.thread, model.ThreadArtifact{
			ID: referenceID, Kind: kind, Repository: repo.GitHub, Title: referenced.Title,
			State: "referenced", Path: evidencePath(referenced.RepositoryRoot, referenced.Path),
			EvidenceID: referenceID,
			UpdatedAt:  referenced.UpdatedAt, Freshness: "current",
		})
	}
}

func evidencePath(root, path string) string {
	if root == "" || filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(root, filepath.FromSlash(path))
}

func ensure(builders map[string]*accumulator, id string, repo config.Repository) *accumulator {
	if builder, exists := builders[id]; exists {
		return builder
	}
	builder := &accumulator{thread: model.Thread{
		ID: id, Aliases: []string{id}, Repositories: []string{repo.GitHub},
		Artifacts: []model.ThreadArtifact{}, Dependencies: []model.ThreadRelation{},
		Implications: []model.ThreadImplication{}, Obligations: []model.ThreadObligation{},
		Evidence: []model.EvidenceRef{}, Attention: []model.AttentionMoment{},
		Confidence: 0.5, InferenceStatus: "not_configured",
	}}
	builders[id] = builder
	return builder
}

func addAliases(builder *accumulator, aliases map[string]string, id string, values ...string) {
	builder.thread.Aliases = append(builder.thread.Aliases, values...)
	for _, value := range values {
		if value != "" {
			aliases[value] = id
		}
	}
	aliases[id] = id
}

func matchingIssueNumber(repository string, urls []string, numbers []int) int {
	for _, value := range urls {
		match := issueURLPattern.FindStringSubmatch(value)
		if len(match) != 3 || !strings.EqualFold(match[1], repository) {
			continue
		}
		number, _ := strconv.Atoi(match[2])
		return number
	}
	if len(numbers) == 1 {
		return numbers[0]
	}
	return 0
}

func issueID(repository string, number int) string {
	return fmt.Sprintf("issue:%s#%d", repository, number)
}

func recent(value, now time.Time, window time.Duration) bool {
	return !value.IsZero() && !value.After(now) && now.Sub(value) <= window
}
