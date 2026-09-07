#!/usr/bin/env bash
# Fetches the prebuilt sqlite3 libraries that package:sqlite3's build hook would
# otherwise download itself. Dart's HttpClient cannot reach github.com from this
# network, so pubspec.yaml points the hook at native/sqlite3/ instead
# (hooks -> user_defines -> sqlite3 -> source: test-sqlite3).
#
# Usage: tool/fetch_sqlite3.sh [release-tag]   (default: sqlite3-3.3.2)
#
# After bumping the sqlite3 dependency, re-run this with the new tag. The
# expected hashes live in
# ~/.pub-cache/hosted/pub.dev/sqlite3-<version>/lib/src/hook/asset_hashes.dart
set -euo pipefail

tag="${1:-sqlite3-3.3.2}"
base="https://github.com/simolus3/sqlite3.dart/releases/download/$tag"
dest="$(cd "$(dirname "$0")/.." && pwd)/native/sqlite3"

# One entry per target the app builds for: iOS device + simulator, macOS,
# Android, and Windows (the host `flutter test` builds for on a Windows dev box).
files=(
  libsqlite3.arm64.ios.dylib
  libsqlite3.arm64.ios_sim.dylib
  libsqlite3.arm64.macos.dylib
  libsqlite3.arm64.android.so
  libsqlite3.arm.android.so
  libsqlite3.x64.android.so
  sqlite3.x64.windows.dll
)

mkdir -p "$dest"
for f in "${files[@]}"; do
  curl -fL --retry 5 --retry-all-errors --max-time 120 -o "$dest/$f" "$base/$f"
  printf '%-32s %s\n' "$f" "$(shasum -a 256 "$dest/$f" | cut -c1-64)"
done

echo
echo "Compare the hashes above against assetNameToSha256Hash in the sqlite3 package."
