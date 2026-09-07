#!/usr/bin/env bash
# Removes the CocoaPods integration from the iOS project. Every iOS plugin is
# already a Swift package (Flutter says so on each build), so CocoaPods only
# adds a second dependency pass — Flutter's own build output recommends
# removing it to cut build time.
#
# The Podfile is the stock Flutter template plus `platform :ios, '15.0'`; the
# Xcode project already sets IPHONEOS_DEPLOYMENT_TARGET = 15.0 in all three
# configurations, so nothing the Podfile enforced is lost.
#
# Run from the repo root:   tool/deintegrate_cocoapods.sh
# Revert if anything looks wrong:
#   git checkout -- ios && rm -rf ios/Pods && (cd ios && pod install)
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f ios/Podfile ]] || { echo "ios/Podfile not found — already deintegrated?"; exit 0; }
command -v pod >/dev/null || { echo "CocoaPods 'pod' not on PATH"; exit 1; }

echo "== pod deintegrate (strips Pods build phases / refs from Runner.xcodeproj)"
(cd ios && pod deintegrate)

echo "== remove Podfile, Podfile.lock, Pods/"
rm -f ios/Podfile ios/Podfile.lock
rm -rf ios/Pods

echo "== drop the Pods project from the workspace"
python3 - <<'PY'
import pathlib
ws = pathlib.Path("ios/Runner.xcworkspace/contents.xcworkspacedata")
s = ws.read_text()
ref = '   <FileRef\n      location = "group:Pods/Pods.xcodeproj">\n   </FileRef>\n'
assert s.count(ref) == 1, "workspace: expected exactly one Pods FileRef"
ws.write_text(s.replace(ref, ""))
for name, line in [
    ("Debug", '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"\n'),
    ("Release", '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"\n'),
]:
    f = pathlib.Path(f"ios/Flutter/{name}.xcconfig")
    t = f.read_text()
    assert t.count(line) == 1, f"{name}.xcconfig: expected one Pods include"
    f.write_text(t.replace(line, ""))
print("workspace + xcconfigs cleaned")
PY

echo "== leftover 'Pods' references in project.pbxproj (expect 0):"
grep -c "Pods" ios/Runner.xcodeproj/project.pbxproj || true

echo "== verification build"
flutter build ios --release 2>&1 | grep -E "CocoaPods|✓ Built|rror|BUILD FAILED|Encountered" || true
echo "Done. The 'still has CocoaPods integration' notice should be gone from the build output above."
