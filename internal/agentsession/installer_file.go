package agentsession

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const maxIntegrationConfig = 16 * 1024 * 1024

type fileSignature struct {
	inode uint64
	size  int64
	mode  os.FileMode
	mtime int64
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
	if !fileOwnedByCurrentUser(info) {
		return nil, nil, errors.New("integration config is not user-owned")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	return data, &fileSignature{inode: fileInode(info), size: info.Size(), mode: info.Mode().Perm(), mtime: info.ModTime().UnixNano()}, nil
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
	defer func() { _ = os.Remove(temporary) }()
	mode := os.FileMode(0o600)
	if previous != nil {
		mode = previous.mode
	}
	if err := file.Chmod(mode); err != nil {
		_ = file.Close()
		return err
	}
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if previous == nil {
		if err := os.Link(temporary, path); err != nil {
			if errors.Is(err, os.ErrExist) {
				return errors.New("integration config changed during update")
			}
			return fmt.Errorf("create integration config: %w", err)
		}
		return nil
	}
	return os.Rename(temporary, path)
}
