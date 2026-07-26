#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
application="${HYPERLITE_APP:-$repository_root/build/Hyperlite.app}"
version="${HYPERLITE_VERSION:-dev}"
commit="${HYPERLITE_COMMIT:-$(git -C "$repository_root" rev-parse --short HEAD)}"
build_date="${HYPERLITE_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

case "$application" in
  "$repository_root"/build/Hyperlite.app) ;;
  *) printf 'HYPERLITE_APP must be %s/build/Hyperlite.app\n' "$repository_root" >&2; exit 2 ;;
esac

rm -rf "$application"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources" "$repository_root/build/helpers"
cp "$repository_root/macos/Hyperlite/Info.plist" "$application/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$application/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$application/Contents/Info.plist"

ldflags="-s -w -X github.com/jamesonstone/hyperlite/internal/cli.Version=$version -X github.com/jamesonstone/hyperlite/internal/cli.Commit=$commit -X github.com/jamesonstone/hyperlite/internal/cli.Date=$build_date"
for architecture in arm64 amd64; do
  (
    cd "$repository_root"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$architecture" go build -trimpath -ldflags "$ldflags" -o "$repository_root/build/helpers/hyperlite-$architecture" ./cmd/hyperlite
  )
done
/usr/bin/lipo -create "$repository_root/build/helpers/hyperlite-arm64" "$repository_root/build/helpers/hyperlite-amd64" -output "$application/Contents/MacOS/hyperlite-cli"

xcrun swiftc -parse-as-library -O -framework SwiftUI -framework AppKit -framework Carbon \
  "$repository_root/macos/Hyperlite/HyperliteApp.swift" \
  "$repository_root/macos/Hyperlite/HyperliteModels.swift" \
  -o "$application/Contents/MacOS/Hyperlite"

/usr/bin/codesign --force --sign - --timestamp=none "$application/Contents/MacOS/hyperlite-cli"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$application"
printf 'built %s\n' "$application"
