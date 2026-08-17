package agentsession

import "strings"

func bridgeCommand(executable, profileID string) string {
	return shellQuote(executable) + " agent hook --profile " + shellQuote(profileID)
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}
