package agentsession

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var (
	tomlBegin = []byte("# BEGIN HYPERLITE MANAGED HOOKS")
	tomlEnd   = []byte("# END HYPERLITE MANAGED HOOKS")
)

func ReconcileIntegration(home, bridgePath, id string, enable bool) (IntegrationStatus, error) {
	profile, ok := ProfileByID(id)
	if !ok {
		return IntegrationStatus{}, fmt.Errorf("unknown integration %q", id)
	}
	if len(EventsForProfile(profile.ID)) == 0 {
		return IntegrationStatus{}, fmt.Errorf("integration %q has no registered events", id)
	}
	target, err := secureTarget(home, preferredTarget(home, profile))
	if err != nil {
		return IntegrationStatus{}, err
	}
	command := bridgeCommand(bridgePath, profile.ID)
	if enable && bridgePath == "" {
		return IntegrationStatus{}, errors.New("bridge executable is required")
	}
	switch profile.Kind {
	case InstallJSON, InstallCopilot:
		err = reconcileJSON(target, profile, command, enable)
	case InstallTOML:
		err = reconcileTOML(target, profile, command, enable)
	case InstallPlugin:
		err = reconcileGeneratedFile(target, pluginContents(profile, command), enable)
	case InstallDirectory:
		err = reconcileGeneratedDirectory(target, profile, command, enable)
	default:
		err = errors.New("unsupported integration kind")
	}
	if err != nil {
		return IntegrationStatus{}, err
	}
	return IntegrationStatus{Schema: IntegrationSchema, ID: profile.ID, Name: profile.Name,
		Provider: profile.Provider, Detected: true, Enabled: enable,
		ActionMode: profile.ActionMode, Target: target}, nil
}

func secureTarget(home, target string) (string, error) {
	if home == "" || target == "" {
		return "", errors.New("integration target is unavailable")
	}
	homeAbs, err := filepath.Abs(home)
	if err != nil {
		return "", err
	}
	homeInfo, err := os.Lstat(homeAbs)
	if err != nil {
		return "", fmt.Errorf("inspect user home: %w", err)
	}
	if !homeInfo.IsDir() || homeInfo.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("user home is not a real directory")
	}
	targetAbs, err := filepath.Abs(target)
	if err != nil {
		return "", err
	}
	relative, err := filepath.Rel(homeAbs, targetAbs)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", errors.New("integration target escapes the user home")
	}
	parent := filepath.Dir(targetAbs)
	for parent != homeAbs && parent != filepath.Dir(parent) {
		if info, statErr := os.Lstat(parent); statErr == nil && info.Mode()&os.ModeSymlink != 0 {
			return "", errors.New("integration target has a symlinked parent")
		}
		parent = filepath.Dir(parent)
	}
	if info, statErr := os.Lstat(targetAbs); statErr == nil && info.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("integration target is a symbolic link")
	}
	return targetAbs, nil
}

func reconcileJSON(path string, profile Profile, command string, enable bool) error {
	data, signature, err := readConfig(path)
	if err != nil {
		return err
	}
	document := make(map[string]any)
	if len(bytes.TrimSpace(data)) > 0 {
		if err := json.Unmarshal(data, &document); err != nil {
			return errors.New("integration JSON is malformed")
		}
	}
	hooks, _ := document["hooks"].(map[string]any)
	if hooks == nil {
		hooks = make(map[string]any)
	}
	for _, event := range EventsForProfile(profile.ID) {
		entries, _ := hooks[event].([]any)
		entries = removeOwnedJSONEntries(entries, profile.ID)
		if enable {
			entries = append(entries, map[string]any{
				"matcher": "*", "hooks": []any{map[string]any{
					"type": "command", "command": command, "timeout": 86400,
					"hyperlite_managed": profile.ID,
				}},
			})
		}
		if len(entries) == 0 {
			delete(hooks, event)
		} else {
			hooks[event] = entries
		}
	}
	if len(hooks) == 0 {
		delete(document, "hooks")
	} else {
		document["hooks"] = hooks
	}
	encoded, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	return writeConfig(path, encoded, signature)
}

func removeOwnedJSONEntries(entries []any, profileID string) []any {
	result := make([]any, 0, len(entries))
	for _, entry := range entries {
		object, objectOK := entry.(map[string]any)
		hooks, hooksOK := object["hooks"].([]any)
		if !objectOK || !hooksOK {
			result = append(result, entry)
			continue
		}
		remaining := make([]any, 0, len(hooks))
		for _, hook := range hooks {
			value, _ := hook.(map[string]any)
			if value["hyperlite_managed"] == profileID {
				continue
			}
			remaining = append(remaining, hook)
		}
		if len(remaining) == 0 {
			continue
		}
		object["hooks"] = remaining
		result = append(result, object)
	}
	return result
}

func reconcileTOML(path string, profile Profile, command string, enable bool) error {
	data, signature, err := readConfig(path)
	if err != nil {
		return err
	}
	data, err = removeManagedBlock(data)
	if err != nil {
		return err
	}
	if enable {
		var block strings.Builder
		block.WriteString(string(tomlBegin) + "\n")
		for _, event := range EventsForProfile(profile.ID) {
			block.WriteString("[[hooks]]\nname = \"")
			block.WriteString(event)
			block.WriteString("\"\ncommand = \"")
			block.WriteString(escapeTOMLBasicString(command))
			block.WriteString("\"\n\n")
		}
		block.WriteString(string(tomlEnd) + "\n")
		data = append(bytes.TrimRight(data, "\n"), '\n', '\n')
		data = append(data, []byte(block.String())...)
	}
	return writeConfig(path, data, signature)
}

func removeManagedBlock(data []byte) ([]byte, error) {
	start := bytes.Index(data, tomlBegin)
	end := bytes.Index(data, tomlEnd)
	if start < 0 && end < 0 {
		return data, nil
	}
	if start < 0 || end < start {
		return nil, errors.New("managed integration block is malformed")
	}
	end += len(tomlEnd)
	for end < len(data) && (data[end] == '\r' || data[end] == '\n') {
		end++
	}
	return append(append([]byte{}, data[:start]...), data[end:]...), nil
}

func reconcileGeneratedFile(path string, contents []byte, enable bool) error {
	if !enable {
		if _, err := os.Lstat(path); errors.Is(err, os.ErrNotExist) {
			return nil
		} else if err != nil {
			return err
		}
		data, _, err := readConfig(path)
		if err != nil {
			return err
		}
		if !bytes.Contains(data, []byte("HYPERLITE MANAGED")) {
			return errors.New("refusing to remove an unowned integration file")
		}
		return os.Remove(path)
	}
	_, signature, err := readConfig(path)
	if err != nil {
		return err
	}
	return writeConfig(path, contents, signature)
}

func reconcileGeneratedDirectory(path string, profile Profile, command string, enable bool) error {
	return reconcileGeneratedFile(filepath.Join(path, "hyperlite.json"), generatedDirectoryContents(profile, command), enable)
}

func pluginContents(profile Profile, command string) []byte {
	profileJSON, _ := json.Marshal(profile.ID)
	commandJSON, _ := json.Marshal(command)
	return []byte("// HYPERLITE MANAGED\nexport const Hyperlite = { profile: " +
		string(profileJSON) + ", command: " + string(commandJSON) + " };\n")
}

func generatedDirectoryContents(profile Profile, command string) []byte {
	data, _ := json.MarshalIndent(map[string]any{"hyperlite_managed": true, "profile": profile.ID,
		"command": command, "events": EventsForProfile(profile.ID)}, "", "  ")
	return append(data, '\n')
}
