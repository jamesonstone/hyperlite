package agentsession

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

const maxIntegrationConfig = 16 * 1024 * 1024

var (
	tomlBegin = []byte("# BEGIN HYPERLITE MANAGED HOOKS")
	tomlEnd   = []byte("# END HYPERLITE MANAGED HOOKS")
)

type fileSignature struct {
	inode uint64
	size  int64
	mode  os.FileMode
	mtime int64
}

func ReconcileIntegration(home, bridgePath, id string, enable bool) (IntegrationStatus, error) {
	profile, ok := ProfileByID(id)
	if !ok {
		return IntegrationStatus{}, fmt.Errorf("unknown integration %q", id)
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
	result := entries[:0]
	for _, entry := range entries {
		object, _ := entry.(map[string]any)
		hooks, _ := object["hooks"].([]any)
		owned := false
		for _, hook := range hooks {
			value, _ := hook.(map[string]any)
			if value["hyperlite_managed"] == profileID {
				owned = true
			}
		}
		if !owned {
			result = append(result, entry)
		}
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
			block.WriteString(strings.ReplaceAll(command, "\"", "\\\""))
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

func readConfig(path string) ([]byte, *fileSignature, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > maxIntegrationConfig {
		return nil, nil, errors.New("integration config is not a bounded regular file")
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || int(stat.Uid) != os.Getuid() {
		return nil, nil, errors.New("integration config is not user-owned")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	return data, &fileSignature{inode: stat.Ino, size: info.Size(), mode: info.Mode().Perm(), mtime: info.ModTime().UnixNano()}, nil
}

func writeConfig(path string, data []byte, previous *fileSignature) error {
	if len(data) > maxIntegrationConfig {
		return errors.New("integration config exceeds the safety limit")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	if previous != nil {
		_, current, err := readConfig(path)
		if err != nil || current == nil || *current != *previous {
			return errors.New("integration config changed during update")
		}
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".hyperlite-integration-*")
	if err != nil {
		return err
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	mode := os.FileMode(0o600)
	if previous != nil {
		mode = previous.mode
	}
	if err := file.Chmod(mode); err != nil {
		file.Close()
		return err
	}
	if _, err := file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}
