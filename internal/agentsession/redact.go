package agentsession

import (
	"fmt"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"
)

var (
	secretKeyPattern  = regexp.MustCompile(`(?i)(authorization|cookie|password|passwd|secret|token|api[_-]?key|private[_-]?key|credential)`)
	bearerPattern     = regexp.MustCompile(`(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]+`)
	assignmentPattern = regexp.MustCompile(`(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|CREDENTIAL)[A-Z0-9_]*)=([^\s]+)`)
	privateKeyPattern = regexp.MustCompile(`(?s)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----`)
	nonWhitespace     = regexp.MustCompile(`\S+`)
)

var allowedArgumentKeys = map[string]struct{}{
	"command": {}, "cmd": {}, "path": {}, "file_path": {}, "cwd": {},
	"domain": {}, "host": {}, "url": {}, "permission": {}, "permissions": {},
	"method": {}, "tool": {}, "resource": {}, "pattern": {},
}

func BoundDisplayText(value string, limit int) string {
	text, _ := boundDisplayText(value, limit)
	return text
}

func boundDisplayText(value string, limit int) (string, bool) {
	value = strings.TrimSpace(strings.ReplaceAll(strings.ReplaceAll(value, "\r\n", "\n"), "\r", "\n"))
	value = privateKeyPattern.ReplaceAllString(value, "[REDACTED PRIVATE KEY]")
	value = bearerPattern.ReplaceAllString(value, "$1 [REDACTED]")
	value = assignmentPattern.ReplaceAllString(value, "$1=[REDACTED]")
	value = redactSignedURLs(value)
	if limit <= 0 || utf8.RuneCountInString(value) <= limit {
		return value, true
	}
	if limit == 1 {
		return "…", false
	}
	return string([]rune(value)[:limit-1]) + "…", false
}

func SanitizeArguments(values map[string]any) (map[string]string, bool) {
	if len(values) == 0 {
		return nil, true
	}
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	result := make(map[string]string)
	complete := true
	for _, key := range keys {
		normalized := strings.ToLower(strings.TrimSpace(key))
		if secretKeyPattern.MatchString(normalized) {
			result[key] = "[REDACTED]"
			complete = false
			continue
		}
		if _, ok := allowedArgumentKeys[normalized]; !ok {
			continue
		}
		text, completeText := boundDisplayText(fmt.Sprint(values[key]), maxActionRunes)
		if text == "" {
			continue
		}
		if !completeText || strings.Contains(text, "[REDACTED") {
			complete = false
		}
		result[key] = text
	}
	return result, complete
}

func redactSignedURLs(value string) string {
	changed := false
	redactedValue := nonWhitespace.ReplaceAllStringFunc(value, func(field string) string {
		trimmed := strings.Trim(field, `<>"'(),`)
		parsed, err := url.Parse(trimmed)
		if err != nil || parsed.Scheme == "" || parsed.Host == "" || parsed.RawQuery == "" {
			return field
		}
		query := parsed.Query()
		redactedURL := false
		for key := range query {
			if secretKeyPattern.MatchString(key) || strings.EqualFold(key, "X-Amz-Signature") {
				query.Set(key, "REDACTED")
				redactedURL = true
			}
		}
		if redactedURL {
			parsed.RawQuery = query.Encode()
			changed = true
			return strings.Replace(field, trimmed, parsed.String(), 1)
		}
		return field
	})
	if !changed {
		return value
	}
	return redactedValue
}

func safeAction(event Event) *PendingAction {
	if !event.ExpectsResponse || event.RequestID == "" || !event.CompleteContext {
		return nil
	}
	context, completeContext := boundDisplayText(event.ActionContext, maxActionRunes)
	arguments, argumentsComplete := SanitizeArguments(event.Arguments)
	if context == "" || !completeContext || !argumentsComplete || strings.Contains(context, "[REDACTED") {
		return nil
	}
	kind := strings.ToLower(event.ActionKind)
	return &PendingAction{
		RequestID: event.RequestID, Kind: kind,
		Title: BoundDisplayText(event.ActionTitle, 240), Context: context,
		Arguments: arguments, CompleteContext: true,
		CanAllowOnce: kind == "approval", CanDeny: kind == "approval",
		CanAnswer: kind == "question",
	}
}
