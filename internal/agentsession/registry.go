package agentsession

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

type InstallKind string

const (
	InstallJSON      InstallKind = "json"
	InstallTOML      InstallKind = "toml"
	InstallPlugin    InstallKind = "plugin"
	InstallDirectory InstallKind = "directory"
	InstallCopilot   InstallKind = "copilot"
)

type Profile struct {
	ID              string
	Name            string
	Provider        string
	ExecutableNames []string
	AppBundles      []string
	Targets         []string
	Kind            InstallKind
	ActionMode      string
}

var profiles = []Profile{
	jsonProfile("claude-code", "Claude Code", "claude", []string{"claude"}, ".claude/settings.json", "blocking"),
	jsonProfile("codex", "Codex", "codex", []string{"codex"}, ".codex/hooks.json", "blocking"),
	jsonProfile("gemini", "Gemini CLI", "gemini", []string{"gemini"}, ".gemini/settings.json", "notify"),
	pluginProfile("antigravity", "Antigravity CLI", "gemini", []string{"antigravity"}, ".gemini/antigravity-cli/plugins/hyperlite", InstallDirectory),
	pluginProfile("hermes", "Hermes", "claude", []string{"hermes"}, ".hermes/plugins/hyperlite", InstallDirectory),
	pluginProfile("pi", "Pi Agent", "claude", []string{"pi"}, ".pi/agent/extensions/hyperlite", InstallDirectory),
	jsonProfile("qwen-code", "Qwen Code", "claude", []string{"qwen"}, ".qwen/settings.json", "blocking"),
	tomlProfile("kimi", "Kimi CLI", "kimi", []string{"kimi"}, []string{".kimi-code/config.toml", ".kimi/config.toml"}),
	pluginProfile("openclaw", "OpenClaw", "claude", []string{"openclaw"}, ".openclaw/hooks/hyperlite", InstallDirectory),
	pluginProfile("opencode", "OpenCode", "claude", []string{"opencode"}, ".config/opencode/plugins/hyperlite.js", InstallPlugin),
	jsonProfile("cursor", "Cursor", "claude", nil, ".cursor/hooks.json", "blocking"),
	jsonProfile("qoder", "Qoder", "claude", nil, ".qoder/settings.json", "notify"),
	jsonProfile("qoder-cli", "Qoder CLI", "claude", []string{"qodercli"}, ".qoder/settings.json", "blocking"),
	jsonProfile("qoder-cn", "Qoder CN", "claude", nil, ".qoder-cn/settings.json", "notify"),
	jsonProfile("qoder-cn-cli", "Qoder CN CLI", "claude", []string{"qoderclicn"}, ".qoder-cn/settings.json", "blocking"),
	jsonProfile("qoderwork", "QoderWork", "claude", nil, ".qoderwork/settings.json", "notify"),
	jsonProfile("codebuddy", "CodeBuddy", "claude", nil, ".codebuddy/settings.json", "notify"),
	jsonProfile("codebuddy-cli", "CodeBuddy CLI", "claude", []string{"codebuddy"}, ".codebuddy/settings.json", "blocking"),
	jsonProfile("workbuddy", "WorkBuddy", "claude", nil, ".workbuddy/settings.json", "notify"),
	{
		ID: "copilot", Name: "GitHub Copilot", Provider: "copilot",
		ExecutableNames: []string{"github-copilot-cli", "copilot"},
		Targets:         []string{".github/hooks/hyperlite.json"}, Kind: InstallCopilot, ActionMode: "notify",
	},
}

var profileApplications = map[string][]string{
	"claude-code": {"Claude.app"}, "codex": {"Codex.app"}, "cursor": {"Cursor.app"},
	"qoder": {"Qoder.app"}, "qoder-cn": {"Qoder CN.app"}, "qoderwork": {"QoderWork.app"},
	"codebuddy": {"CodeBuddy.app"}, "workbuddy": {"WorkBuddy.app"}, "opencode": {"OpenCode.app"},
	"copilot": {"GitHub Copilot.app"},
}

func jsonProfile(id, name, provider string, executables []string, target, mode string) Profile {
	return Profile{ID: id, Name: name, Provider: provider, ExecutableNames: executables,
		Targets: []string{target}, Kind: InstallJSON, ActionMode: mode}
}

func tomlProfile(id, name, provider string, executables, targets []string) Profile {
	return Profile{ID: id, Name: name, Provider: provider, ExecutableNames: executables,
		Targets: targets, Kind: InstallTOML, ActionMode: "notify"}
}

func pluginProfile(id, name, provider string, executables []string, target string, kind InstallKind) Profile {
	return Profile{ID: id, Name: name, Provider: provider, ExecutableNames: executables,
		Targets: []string{target}, Kind: kind, ActionMode: "notify"}
}

func Profiles() []Profile {
	result := make([]Profile, len(profiles))
	copy(result, profiles)
	return result
}

func ProfileByID(id string) (Profile, bool) {
	for _, profile := range profiles {
		if profile.ID == id {
			return profile, true
		}
	}
	return Profile{}, false
}

func DetectIntegrations(home, bridgePath string) []IntegrationStatus {
	result := make([]IntegrationStatus, 0, len(profiles))
	for _, profile := range profiles {
		detected := profileDetected(home, profile)
		target := preferredTarget(home, profile)
		result = append(result, IntegrationStatus{
			Schema: IntegrationSchema, ID: profile.ID, Name: profile.Name,
			Provider: profile.Provider, Detected: detected,
			Enabled: integrationEnabled(target, bridgePath), ActionMode: profile.ActionMode,
			Target: target,
		})
	}
	return result
}

func profileDetected(home string, profile Profile) bool {
	for _, name := range profile.ExecutableNames {
		if _, err := exec.LookPath(name); err == nil {
			return true
		}
	}
	for _, target := range profile.Targets {
		if _, err := os.Lstat(filepath.Join(home, target)); err == nil {
			return true
		}
	}
	for _, bundle := range profile.AppBundles {
		if _, err := os.Stat(filepath.Join("/Applications", bundle)); err == nil {
			return true
		}
	}
	for _, appName := range profileApplications[profile.ID] {
		if _, err := os.Stat(filepath.Join("/Applications", appName)); err == nil {
			return true
		}
		if _, err := os.Stat(filepath.Join(home, "Applications", appName)); err == nil {
			return true
		}
	}
	return false
}

func preferredTarget(home string, profile Profile) string {
	for _, target := range profile.Targets {
		candidate := filepath.Join(home, target)
		if _, err := os.Lstat(candidate); err == nil {
			return candidate
		}
	}
	if len(profile.Targets) == 0 {
		return ""
	}
	return filepath.Join(home, profile.Targets[0])
}

func integrationEnabled(target, bridgePath string) bool {
	if target == "" {
		return false
	}
	data, err := readOwnedIntegrationFile(target)
	if err != nil {
		data, err = readOwnedIntegrationFile(filepath.Join(target, "hyperlite.json"))
	}
	if err != nil || len(data) > 16*1024*1024 {
		return false
	}
	text := string(data)
	return strings.Contains(text, "hyperlite agent hook") ||
		(bridgePath != "" && strings.Contains(text, bridgePath))
}

func readOwnedIntegrationFile(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maxIntegrationConfig {
		return nil, os.ErrNotExist
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || int(stat.Uid) != os.Getuid() {
		return nil, os.ErrPermission
	}
	return os.ReadFile(path)
}
