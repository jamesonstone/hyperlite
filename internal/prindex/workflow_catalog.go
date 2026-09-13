package prindex

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

type CatalogEntry struct {
	TreeOID string
	Catalog []model.WorkflowDefinition
	Error   string
}

type CatalogResult struct {
	Repositories map[string]CatalogEntry
	RateLimit    *GitHubRateLimit
}

type rawWorkflowTreeEntry struct {
	Name   string `json:"name"`
	Type   string `json:"type"`
	Object *struct {
		Text        string `json:"text"`
		IsTruncated bool   `json:"isTruncated"`
	} `json:"object"`
}

type rawWorkflowTree struct {
	OID     string                 `json:"oid"`
	Entries []rawWorkflowTreeEntry `json:"entries"`
}

type rawCatalogRepository struct {
	Object *rawWorkflowTree `json:"object"`
}

// FetchCatalogs reads workflow definitions for repositories whose workflows
// tree changed. A repository without a workflows directory yields an empty
// catalog rather than an error.
func (c GitHubClient) FetchCatalogs(
	ctx context.Context,
	repositories []config.Repository,
) CatalogResult {
	unique := uniqueRepositories(repositories)
	result := CatalogResult{Repositories: make(map[string]CatalogEntry, len(unique))}
	collector := rateLimitCollector{}
	for start := 0; start < len(unique); start += queryBatchSize {
		batch := unique[start:min(start+queryBatchSize, len(unique))]
		query, aliases := buildWorkflowCatalogQuery(batch)
		output, err := c.run(ctx, query)
		if err != nil {
			setCatalogError(result.Repositories, batch, err.Error())
			continue
		}
		var response rawResponse
		if err := json.Unmarshal(output, &response); err != nil {
			setCatalogError(result.Repositories, batch, "decode GraphQL response: "+err.Error())
			continue
		}
		collector.observe(response.Data)
		errorsByAlias, globalErrors := graphQLErrors(response.Errors)
		for alias, repository := range aliases {
			key := repositoryKey(repository.GitHub)
			messages := append(append([]string{}, globalErrors...), errorsByAlias[alias]...)
			raw, found, decodeErr := decodeGraphQLData[rawCatalogRepository](response.Data, alias)
			switch {
			case decodeErr != nil:
				result.Repositories[key] = CatalogEntry{Error: "decode GitHub workflow data: " + decodeErr.Error()}
			case !found || raw == nil:
				if len(messages) == 0 {
					messages = append(messages, "GitHub returned no repository data")
				}
				result.Repositories[key] = CatalogEntry{Error: strings.Join(messages, "; ")}
			case len(messages) > 0:
				result.Repositories[key] = CatalogEntry{Error: strings.Join(messages, "; ")}
			default:
				result.Repositories[key] = catalogEntry(repository.GitHub, raw.Object)
			}
		}
	}
	result.RateLimit = collector.latest
	return result
}

func setCatalogError(results map[string]CatalogEntry, repositories []config.Repository, message string) {
	for _, repository := range repositories {
		results[repositoryKey(repository.GitHub)] = CatalogEntry{Error: message}
	}
}

func catalogEntry(github string, tree *rawWorkflowTree) CatalogEntry {
	entry := CatalogEntry{Catalog: []model.WorkflowDefinition{}}
	if tree == nil {
		return entry
	}
	entry.TreeOID = strings.TrimSpace(tree.OID)
	entry.Catalog = parseWorkflowCatalog(github, tree.Entries)
	return entry
}

// parseWorkflowCatalog keeps YAML workflow files in tree order and derives the
// display name from the top-level `name:` key, falling back to the file name.
func parseWorkflowCatalog(github string, entries []rawWorkflowTreeEntry) []model.WorkflowDefinition {
	catalog := []model.WorkflowDefinition{}
	for _, entry := range entries {
		file := strings.TrimSpace(entry.Name)
		if entry.Type != "blob" || !isWorkflowFile(file) {
			continue
		}
		name := workflowDisplayName(file)
		if entry.Object != nil && !entry.Object.IsTruncated {
			if parsed, found := workflowNameFromYAML(entry.Object.Text); found {
				name = parsed
			}
		}
		catalog = append(catalog, model.WorkflowDefinition{
			File: file, Name: name,
			URL: "https://github.com/" + strings.TrimSpace(github) + "/actions/workflows/" + file,
		})
	}
	return catalog
}

func isWorkflowFile(file string) bool {
	lower := strings.ToLower(file)
	return strings.HasSuffix(lower, ".yml") || strings.HasSuffix(lower, ".yaml")
}

// workflowNameFromYAML scans for the first unindented `name:` line. It avoids
// a YAML parser because workflow files are untrusted and only one scalar is
// needed.
func workflowNameFromYAML(text string) (string, bool) {
	for _, line := range strings.Split(text, "\n") {
		if !strings.HasPrefix(line, "name:") {
			continue
		}
		value := strings.TrimSpace(strings.TrimPrefix(line, "name:"))
		value = stripYAMLComment(value)
		value = strings.TrimSpace(value)
		if len(value) >= 2 {
			if quote := value[0]; (quote == '"' || quote == '\'') && value[len(value)-1] == quote {
				value = value[1 : len(value)-1]
			}
		}
		if value = strings.TrimSpace(value); value != "" {
			return value, true
		}
		return "", false
	}
	return "", false
}

func stripYAMLComment(value string) string {
	if value == "" {
		return value
	}
	if quote := value[0]; quote == '"' || quote == '\'' {
		if end := strings.IndexByte(value[1:], quote); end >= 0 {
			return value[:end+2]
		}
		return value
	}
	if index := strings.Index(value, " #"); index >= 0 {
		return value[:index]
	}
	if strings.HasPrefix(value, "#") {
		return ""
	}
	return value
}
