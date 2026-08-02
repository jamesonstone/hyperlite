#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
application="${HYPERLITE_APP:-$repository_root/build/Hyperlite.app}"
version="${HYPERLITE_VERSION:-dev}"
commit="${HYPERLITE_COMMIT:-$(git -C "$repository_root" rev-parse --short HEAD)}"
build_date="${HYPERLITE_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
build_number_file="$repository_root/build/.hyperlite-build-number"

case "$application" in
  "$repository_root"/build/Hyperlite.app) ;;
  *) printf 'HYPERLITE_APP must be %s/build/Hyperlite.app\n' "$repository_root" >&2; exit 2 ;;
esac

rm -rf "$application"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources" "$repository_root/build/helpers"
build_number="$(date -u +%s)"
if [[ -f "$build_number_file" ]]; then
  previous_build_number="$(<"$build_number_file")"
  if [[ ! "$previous_build_number" =~ ^[0-9]+$ ]]; then
    printf 'invalid build number in %s\n' "$build_number_file" >&2
    exit 2
  fi
  if (( previous_build_number >= build_number )); then
    build_number=$((previous_build_number + 1))
  fi
fi
printf '%s\n' "$build_number" > "$build_number_file"
cp "$repository_root/macos/Hyperlite/Info.plist" "$application/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$application/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$application/Contents/Info.plist"

icon_source="$repository_root/macos/Hyperlite/Assets/HyperliteIcon.png"
iconset="$repository_root/build/Hyperlite.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  double_size=$((size * 2))
  /usr/bin/sips -z "$size" "$size" "$icon_source" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -z "$double_size" "$double_size" "$icon_source" \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$application/Contents/Resources/Hyperlite.icns"
rm -rf "$iconset"

ldflags="-s -w -X github.com/jamesonstone/hyperlite/internal/cli.Version=$version -X github.com/jamesonstone/hyperlite/internal/cli.Commit=$commit -X github.com/jamesonstone/hyperlite/internal/cli.Date=$build_date"
for architecture in arm64 amd64; do
  (
    cd "$repository_root"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$architecture" go build -trimpath -ldflags "$ldflags" -o "$repository_root/build/helpers/hyperlite-$architecture" ./cmd/hyperlite
  )
done
/usr/bin/lipo -create "$repository_root/build/helpers/hyperlite-arm64" "$repository_root/build/helpers/hyperlite-amd64" -output "$application/Contents/MacOS/hyperlite-cli"

swift_sources=("$repository_root"/macos/Hyperlite/*.swift)
for architecture in arm64 x86_64; do
  xcrun swiftc -parse-as-library -O -target "$architecture-apple-macos13.0" -framework SwiftUI -framework AppKit -framework Carbon -framework NaturalLanguage -lsqlite3 \
    "${swift_sources[@]}" \
    -o "$repository_root/build/helpers/Hyperlite-$architecture"
done
/usr/bin/lipo -create "$repository_root/build/helpers/Hyperlite-arm64" "$repository_root/build/helpers/Hyperlite-x86_64" -output "$application/Contents/MacOS/Hyperlite"

/usr/bin/codesign --force --sign - --timestamp=none "$application/Contents/MacOS/hyperlite-cli"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$application"
printf 'built %s\n' "$application"
