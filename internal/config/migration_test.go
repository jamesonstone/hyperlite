package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolvePathPrecedence(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("HYPERLITE_CONFIG", filepath.Join(home, "environment.yaml"))

	path, err := ResolvePath("explicit.yaml")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(path, "explicit.yaml") {
		t.Fatalf("explicit path = %q", path)
	}

	path, err = ResolvePath("")
	if err != nil {
		t.Fatal(err)
	}
	if path != filepath.Join(home, "environment.yaml") {
		t.Fatalf("environment path = %q", path)
	}

	t.Setenv("HYPERLITE_CONFIG", "")
	path, err = ResolvePath("")
	if err != nil {
		t.Fatal(err)
	}
	if path != filepath.Join(home, ".config", "hyperlite", "config.yaml") {
		t.Fatalf("default path = %q", path)
	}
}

func TestEnsureDefaultConfigCopiesBeaconConfigOnce(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	beaconPath := filepath.Join(home, ".config", "beacon", "config.yaml")
	contents := []byte("version: 2\nprojects: []\n# retain this exact content\n")
	if err := os.MkdirAll(filepath.Dir(beaconPath), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(beaconPath, contents, 0o600); err != nil {
		t.Fatal(err)
	}

	path, err := EnsureDefaultConfig("")
	if err != nil {
		t.Fatal(err)
	}
	written, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(written) != string(contents) {
		t.Fatalf("migrated config = %q", written)
	}
	if err := os.WriteFile(path, []byte("hyperlite owns this now\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := EnsureDefaultConfig(""); err != nil {
		t.Fatal(err)
	}
	written, err = os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(written) != "hyperlite owns this now\n" {
		t.Fatalf("existing Hyperlite config was overwritten: %q", written)
	}
}

func TestEnsureDefaultConfigRejectsNonRegularBeaconConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	beaconPath := filepath.Join(home, ".config", "beacon", "config.yaml")
	if err := os.MkdirAll(beaconPath, 0o700); err != nil {
		t.Fatal(err)
	}

	_, err := EnsureDefaultConfig("")
	if err == nil {
		t.Fatal("EnsureDefaultConfig() error = nil")
	}
	if !strings.Contains(err.Error(), "Beacon config is not a regular file") {
		t.Fatalf("EnsureDefaultConfig() error = %q", err)
	}
	if _, statErr := os.Stat(filepath.Join(home, ".config", "hyperlite", "config.yaml")); !os.IsNotExist(statErr) {
		t.Fatalf("Hyperlite config stat error = %v, want not exist", statErr)
	}
}
