package agentsession

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"time"
)

const (
	routingVersion = 1
	routingTTL     = 24 * time.Hour
	maxRoutingFile = 2 * 1024 * 1024
)

type RoutingRecord struct {
	Provider  string    `json:"provider"`
	Profile   string    `json:"profile"`
	SessionID string    `json:"session_id"`
	Routing   Routing   `json:"routing"`
	LastSeen  time.Time `json:"last_seen"`
}

type routingFile struct {
	Version int             `json:"version"`
	Records []RoutingRecord `json:"records"`
}

func RoutingPath(environment map[string]string, home string) (string, error) {
	root := environment["XDG_STATE_HOME"]
	if root == "" {
		if home == "" {
			resolved, err := os.UserHomeDir()
			if err != nil {
				return "", fmt.Errorf("resolve home directory: %w", err)
			}
			home = resolved
		}
		root = filepath.Join(home, ".local", "state")
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve routing state directory: %w", err)
	}
	return filepath.Join(filepath.Clean(abs), "hyperlite", "agent-routing.json"), nil
}

func LoadRouting(path string, now time.Time) ([]RoutingRecord, error) {
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return []RoutingRecord{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("open routing state: %w", err)
	}
	defer func() { _ = file.Close() }()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > maxRoutingFile {
		return nil, errors.New("routing state is not a bounded regular file")
	}
	data, err := io.ReadAll(io.LimitReader(file, maxRoutingFile+1))
	if err != nil || len(data) > maxRoutingFile {
		return nil, errors.New("routing state exceeds the safety limit")
	}
	var decoded routingFile
	if err := json.Unmarshal(data, &decoded); err != nil || decoded.Version != routingVersion {
		return nil, errors.New("routing state is malformed")
	}
	return pruneRouting(decoded.Records, now), nil
}

func SaveRouting(path string, records []RoutingRecord, now time.Time) error {
	records = pruneRouting(records, now)
	sort.Slice(records, func(i, j int) bool {
		if records[i].Provider != records[j].Provider {
			return records[i].Provider < records[j].Provider
		}
		return records[i].SessionID < records[j].SessionID
	})
	data, err := json.Marshal(routingFile{Version: routingVersion, Records: records})
	if err != nil {
		return fmt.Errorf("encode routing state: %w", err)
	}
	if len(data) > maxRoutingFile {
		return errors.New("routing state exceeds the safety limit")
	}
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return fmt.Errorf("create routing state directory: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return fmt.Errorf("secure routing state directory: %w", err)
	}
	file, err := os.CreateTemp(directory, ".agent-routing-*.json")
	if err != nil {
		return fmt.Errorf("create temporary routing state: %w", err)
	}
	temporary := file.Name()
	defer func() { _ = os.Remove(temporary) }()
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return fmt.Errorf("secure temporary routing state: %w", err)
	}
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return fmt.Errorf("write routing state: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return fmt.Errorf("sync routing state: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close routing state: %w", err)
	}
	if err := os.Rename(temporary, path); err != nil {
		return fmt.Errorf("replace routing state: %w", err)
	}
	return nil
}

func RemoveRoutingProfile(path, profile string, now time.Time) error {
	records, err := LoadRouting(path, now)
	if err != nil {
		return err
	}
	filtered := records[:0]
	for _, record := range records {
		if record.Profile != profile {
			filtered = append(filtered, record)
		}
	}
	return SaveRouting(path, filtered, now)
}

func pruneRouting(records []RoutingRecord, now time.Time) []RoutingRecord {
	result := make([]RoutingRecord, 0, len(records))
	seen := make(map[string]int)
	for _, record := range records {
		if record.Provider == "" || record.SessionID == "" || record.LastSeen.IsZero() ||
			now.Sub(record.LastSeen) > routingTTL || record.LastSeen.After(now.Add(time.Minute)) {
			continue
		}
		key := Identity(record.Provider, record.SessionID)
		if index, exists := seen[key]; exists {
			if record.LastSeen.After(result[index].LastSeen) {
				result[index] = record
			}
			continue
		}
		seen[key] = len(result)
		result = append(result, record)
	}
	return result
}
