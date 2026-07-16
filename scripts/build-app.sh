#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

swift build -c release

APP="$ROOT/dist/Codex Monitor.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/CodexMeter" "$CONTENTS/MacOS/CodexMeter"
cp "$ROOT/Sources/CodexMeter/Resources/cli-proxy-api-plus" "$CONTENTS/Resources/cli-proxy-api-plus"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"
chmod 755 "$CONTENTS/Resources/cli-proxy-api-plus"

/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Codex Monitor' \
  -c 'Add :CFBundleDisplayName string Codex Monitor' \
  -c 'Add :CFBundleIdentifier string com.codexmeter.macos' \
  -c 'Add :CFBundleVersion string 1' \
  -c 'Add :CFBundleShortVersionString string 1.0.0' \
  -c 'Add :CFBundleExecutable string CodexMeter' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :LSMinimumSystemVersion string 14.0' \
  -c 'Add :NSHighResolutionCapable bool true' \
  "$CONTENTS/Info.plist"

codesign --force --deep --sign - "$APP"
echo "$APP"
