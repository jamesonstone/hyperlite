package prindex

import (
	"encoding/json"
	"strconv"
	"strings"
)

func buildQuery(requests []pageRequest) (string, map[string]pageRequest) {
	var query strings.Builder
	query.WriteString("query {\n")
	aliases := make(map[string]pageRequest, len(requests))
	for index, request := range requests {
		owner, name, _ := strings.Cut(request.repository.GitHub, "/")
		alias := "repository" + strconv.Itoa(index)
		aliases[alias] = request
		query.WriteString("  ")
		query.WriteString(alias)
		query.WriteString(": repository(owner: ")
		query.WriteString(strconv.Quote(owner))
		query.WriteString(", name: ")
		query.WriteString(strconv.Quote(name))
		query.WriteString(") {\n")
		query.WriteString("    pullRequests(states: OPEN, first: ")
		query.WriteString(strconv.Itoa(queryPageSize))
		if request.cursor != "" {
			query.WriteString(", after: ")
			query.WriteString(strconv.Quote(request.cursor))
		}
		query.WriteString(", orderBy: {field: UPDATED_AT, direction: DESC}) {\n")
		query.WriteString("      nodes {\n")
		query.WriteString("        number title url headRefName headRefOid isDraft mergeable updatedAt\n")
		writeReviewThreadConnection(&query, "        ", "")
		query.WriteString("      }\n")
		query.WriteString("      pageInfo { hasNextPage endCursor }\n")
		query.WriteString("    }\n")
		query.WriteString("  }\n")
	}
	writeRateLimit(&query)
	query.WriteString("}\n")
	return query.String(), aliases
}

func buildReviewThreadQuery(
	requests []reviewThreadPageRequest,
) (string, map[string]reviewThreadPageRequest) {
	var query strings.Builder
	query.WriteString("query {\n")
	aliases := make(map[string]reviewThreadPageRequest, len(requests))
	for index, request := range requests {
		owner, name, _ := strings.Cut(request.repository.GitHub, "/")
		alias := "repository" + strconv.Itoa(index)
		aliases[alias] = request
		query.WriteString("  ")
		query.WriteString(alias)
		query.WriteString(": repository(owner: ")
		query.WriteString(strconv.Quote(owner))
		query.WriteString(", name: ")
		query.WriteString(strconv.Quote(name))
		query.WriteString(") {\n")
		query.WriteString("    pullRequest(number: ")
		query.WriteString(strconv.Itoa(request.pullRequestNumber))
		query.WriteString(") {\n")
		writeReviewThreadConnection(&query, "      ", request.cursor)
		query.WriteString("    }\n")
		query.WriteString("  }\n")
	}
	writeRateLimit(&query)
	query.WriteString("}\n")
	return query.String(), aliases
}

func writeReviewThreadConnection(query *strings.Builder, indent, cursor string) {
	query.WriteString(indent)
	query.WriteString("reviewThreads(first: ")
	query.WriteString(strconv.Itoa(reviewThreadPageSize))
	if cursor != "" {
		query.WriteString(", after: ")
		query.WriteString(strconv.Quote(cursor))
	}
	query.WriteString(") {\n")
	query.WriteString(indent)
	query.WriteString("  nodes { isResolved isOutdated }\n")
	query.WriteString(indent)
	query.WriteString("  pageInfo { hasNextPage endCursor }\n")
	query.WriteString(indent)
	query.WriteString("}\n")
}

func writeRateLimit(query *strings.Builder) {
	query.WriteString("  rateLimit { limit used remaining resetAt cost nodeCount }\n")
}

func graphQLErrors(values []rawGraphQLError) (map[string][]string, []string) {
	byAlias := make(map[string][]string)
	var global []string
	for _, value := range values {
		if len(value.Path) == 0 {
			global = append(global, value.Message)
			continue
		}
		var alias string
		if err := json.Unmarshal(value.Path[0], &alias); err != nil || alias == "" {
			global = append(global, value.Message)
			continue
		}
		byAlias[alias] = append(byAlias[alias], value.Message)
	}
	return byAlias, global
}
