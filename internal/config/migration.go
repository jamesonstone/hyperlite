package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

func ResolvePath(explicit string) (string, error) {
	if explicit != "" {
		return CanonicalizePath(explicit)
	}
	if value := os.Getenv("HYPERLITE_CONFIG"); value != "" {
		return CanonicalizePath(value)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(home, ".config", "hyperlite", "config.yaml"), nil
}

// EnsureDefaultConfig makes Hyperlite's first-run migration explicit and
// one-way. A previously configured Beacon installation gives Hyperlite a
// useful starting selection, but Hyperlite never reads it again after copying.
// Explicit and environment-selected paths remain fully caller-owned.
func EnsureDefaultConfig(explicit string) (string, error) {
	path, err := ResolvePath(explicit)
	if err != nil {
		return "", err
	}
	if explicit != "" || os.Getenv("HYPERLITE_CONFIG") != "" {
		return path, nil
	}
	if _, err := os.Lstat(path); err == nil {
		return path, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("inspect Hyperlite config %s: %w", path, err)
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	beaconPath := filepath.Join(home, ".config", "beacon", "config.yaml")
	contents, err := os.ReadFile(beaconPath)
	if errors.Is(err, os.ErrNotExist) {
		return path, nil
	}
	if err != nil {
		return "", fmt.Errorf("read Beacon config %s: %w", beaconPath, err)
	}
	info, err := os.Stat(beaconPath)
	if err != nil {
		return "", fmt.Errorf("inspect Beacon config %s: %w", beaconPath, err)
	}
	if !info.Mode().IsRegular() {
		return "", fmt.Errorf("Beacon config is not a regular file: %s", beaconPath)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", fmt.Errorf("create Hyperlite config directory: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".config.yaml-*")
	if err != nil {
		return "", fmt.Errorf("create Hyperlite config migration file: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(info.Mode().Perm()); err != nil {
		temporary.Close()
		return "", fmt.Errorf("set Hyperlite config permissions: %w", err)
	}
	if _, err := temporary.Write(contents); err != nil {
		temporary.Close()
		return "", fmt.Errorf("write Hyperlite config migration: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return "", fmt.Errorf("close Hyperlite config migration: %w", err)
	}
	if err := os.Link(temporaryPath, path); err != nil {
		if errors.Is(err, os.ErrExist) {
			return path, nil
		}
		return "", fmt.Errorf("install Hyperlite config migration: %w", err)
	}
	return path, nil
}
