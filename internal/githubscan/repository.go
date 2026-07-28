package githubscan

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func (c Client) collectRepository(
	ctx context.Context,
	repository config.Repository,
	scope, author string,
	anchorIssueNumbers []int,
) model.RemoteEvidence {
	evidence := emptyEvidence()
	prArguments := []string{"pr", "list", "--repo", repository.GitHub, "--state", "all", "--limit", strconv.Itoa(searchLimit), "--json", pullRequestFields}
	if scope != "all" {
		prArguments = append(prArguments, "--author", author)
	}
	prOutput, err := c.run(ctx, "gh", prArguments...)
	if err != nil {
		evidence.Errors = append(evidence.Errors, model.ScanError{Repository: repository.Name, Stage: "github-prs", Message: err.Error()})
	} else if pullRequests, parseErr := parsePullRequests(prOutput); parseErr != nil {
		evidence.Errors = append(evidence.Errors, model.ScanError{Repository: repository.Name, Stage: "github-prs", Message: parseErr.Error()})
	} else {
		evidence.PullRequests = pullRequests
		if len(pullRequests) == searchLimit {
			evidence.Warnings = append(evidence.Warnings, model.ScanError{Repository: repository.Name, Stage: "github-prs", Message: "result limit reached; pull requests may be truncated"})
		}
		var closingIssues []model.Issue
		for index := range evidence.PullRequests {
			closingIssues = append(closingIssues, evidence.PullRequests[index].ClosingIssues...)
			if !strings.EqualFold(evidence.PullRequests[index].State, "OPEN") {
				continue
			}
			threads, count, truncated, threadErr := c.reviewThreadDetails(ctx, repository.GitHub, evidence.PullRequests[index].Number)
			if threadErr != nil {
				evidence.PullRequests[index].ReviewDecision = "UNKNOWN"
				evidence.Errors = append(evidence.Errors, model.ScanError{Repository: repository.Name, Stage: "github-feedback", Message: threadErr.Error()})
				continue
			}
			evidence.PullRequests[index].Feedback.UnresolvedThreads = count
			evidence.PullRequests[index].Feedback.Threads = threads
			evidence.PullRequests[index].Feedback.ThreadsTruncated = truncated
			if truncated {
				evidence.Warnings = append(evidence.Warnings, model.ScanError{Repository: repository.Name, Stage: "github-feedback", Message: fmt.Sprintf("PR #%d review threads may be truncated", evidence.PullRequests[index].Number)})
			}
		}
		evidence.Issues = mergeIssues(evidence.Issues, closingIssues)
	}
	issueArguments := []string{"issue", "list", "--repo", repository.GitHub, "--state", "all", "--limit", strconv.Itoa(searchLimit), "--json", "number,title,body,url,state,updatedAt,closedAt,labels,assignees"}
	if scope != "all" {
		issueArguments = append(issueArguments, "--assignee", author)
	}
	issueOutput, err := c.run(ctx, "gh", issueArguments...)
	if err != nil {
		evidence.Errors = append(evidence.Errors, model.ScanError{Repository: repository.Name, Stage: "github-issues", Message: err.Error()})
	} else if issues, parseErr := parseIssues(issueOutput); parseErr != nil {
		evidence.Errors = append(evidence.Errors, model.ScanError{Repository: repository.Name, Stage: "github-issues", Message: parseErr.Error()})
	} else {
		evidence.Issues = mergeIssues(evidence.Issues, issues)
		if len(issues) == searchLimit {
			evidence.Warnings = append(evidence.Warnings, model.ScanError{Repository: repository.Name, Stage: "github-issues", Message: "result limit reached; issues may be truncated"})
		}
	}
	if len(anchorIssueNumbers) > anchorIssueLimit {
		evidence.Warnings = append(evidence.Warnings, model.ScanError{
			Repository: repository.Name, Stage: "github-issues",
			Message: fmt.Sprintf("exact issue hydration limited to %d anchors", anchorIssueLimit),
		})
		anchorIssueNumbers = anchorIssueNumbers[:anchorIssueLimit]
	}
	knownIssues := make(map[int]struct{}, len(evidence.Issues))
	for _, issue := range evidence.Issues {
		knownIssues[issue.Number] = struct{}{}
	}
	for _, number := range anchorIssueNumbers {
		if _, exists := knownIssues[number]; exists {
			continue
		}
		output, viewErr := c.run(
			ctx, "gh", "issue", "view", strconv.Itoa(number), "--repo", repository.GitHub,
			"--json", "number,title,body,url,state,updatedAt,closedAt,labels,assignees",
		)
		if viewErr != nil {
			evidence.Errors = append(evidence.Errors, model.ScanError{
				Repository: repository.Name, Stage: "github-issue",
				Message: fmt.Sprintf("issue #%d: %v", number, viewErr),
			})
			continue
		}
		var raw rawIssue
		if decodeErr := json.Unmarshal(output, &raw); decodeErr != nil {
			evidence.Errors = append(evidence.Errors, model.ScanError{
				Repository: repository.Name, Stage: "github-issue",
				Message: fmt.Sprintf("issue #%d: decode: %v", number, decodeErr),
			})
			continue
		}
		evidence.Issues = mergeIssues(evidence.Issues, []model.Issue{normalizeIssue(raw)})
		knownIssues[number] = struct{}{}
	}
	sort.Slice(evidence.Issues, func(i, j int) bool {
		return evidence.Issues[i].Number < evidence.Issues[j].Number
	})
	return evidence
}

func mergeIssues(existing, additions []model.Issue) []model.Issue {
	byNumber := make(map[int]model.Issue, len(existing)+len(additions))
	for _, issue := range existing {
		byNumber[issue.Number] = issue
	}
	for _, issue := range additions {
		byNumber[issue.Number] = issue
	}
	result := make([]model.Issue, 0, len(byNumber))
	for _, issue := range byNumber {
		result = append(result, issue)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Number < result[j].Number })
	return result
}
