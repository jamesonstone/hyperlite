#!/usr/bin/env bash
# Idempotent Cloud Agent install. Builds keep disk state and discard shell exports.
set -euo pipefail

go_version=1.26.5

case "$(uname -m)" in
  x86_64) go_arch=amd64 ;;
  aarch64 | arm64) go_arch=arm64 ;;
  *)
    printf 'unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

if ! command -v make >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y make ca-certificates curl git
fi

current=""
if command -v go >/dev/null 2>&1; then
  current="$(go env GOVERSION 2>/dev/null || true)"
fi
if [[ "$current" != "go${go_version}" ]]; then
  tarball="go${go_version}.linux-${go_arch}.tar.gz"
  curl -fsSL "https://go.dev/dl/${tarball}" -o "/tmp/${tarball}"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "/tmp/${tarball}"
  rm -f "/tmp/${tarball}"
fi
sudo ln -sfn /usr/local/go/bin/go /usr/local/bin/go
sudo ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt

cd "$(dirname "$0")/.."
go mod download
