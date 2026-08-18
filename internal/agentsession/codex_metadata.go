package agentsession

import (
	"strconv"
	"strings"
	"time"
)

func codexAuxiliaryKind(thread map[string]any) string {
	kind := firstString(thread, "sourceKind", "source_kind", "sessionKind", "session_kind")
	if kind == "" {
		if source, ok := thread["source"].(map[string]any); ok {
			kind = firstString(source, "kind", "type")
		}
	}
	lower := strings.ToLower(kind)
	if strings.Contains(lower, "compact") || strings.Contains(lower, "title") ||
		strings.Contains(lower, "maintenance") {
		return kind
	}
	return ""
}

func firstBool(values map[string]any, keys ...string) bool {
	for _, key := range keys {
		if value, ok := values[key].(bool); ok && value {
			return true
		}
	}
	return false
}

func firstTime(values map[string]any, keys ...string) time.Time {
	text := firstString(values, keys...)
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339} {
		if parsed, err := time.Parse(layout, text); err == nil {
			return parsed
		}
	}
	if value, err := strconv.ParseInt(text, 10, 64); err == nil {
		if value > 1_000_000_000_000 {
			return time.UnixMilli(value)
		}
		if value > 0 {
			return time.Unix(value, 0)
		}
	}
	return time.Time{}
}
