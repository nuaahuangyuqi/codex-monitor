#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP_NAME="大同"
VERSION="${APP_VERSION:-1.4.3}"
BUILD_NUMBER="${APP_BUILD:-9}"
ARM_SCRATCH="$ROOT/.build/release-arm64"
X86_SCRATCH="$ROOT/.build/release-x86_64"

swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "$ARM_SCRATCH"
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$X86_SCRATCH"

ARM_BIN_DIR="$(swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "$ARM_SCRATCH" --show-bin-path)"
X86_BIN_DIR="$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$X86_SCRATCH" --show-bin-path)"

APP="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/AppIcon"
lipo -create \
  "$ARM_BIN_DIR/CodexMeter" \
  "$X86_BIN_DIR/CodexMeter" \
  -output "$CONTENTS/MacOS/CodexMeter"

cp "$ROOT/Sources/CodexMeter/Resources/AppIcon/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT/Sources/CodexMeter/Resources/AppIcon/AppIconDefault.png" "$CONTENTS/Resources/AppIcon/AppIconDefault.png"
cp "$ROOT/Sources/CodexMeter/Resources/AppIcon/AppIconDark.png" "$CONTENTS/Resources/AppIcon/AppIconDark.png"
cp "$ROOT/Sources/CodexMeter/Resources/AppIcon/AppIconMono.png" "$CONTENTS/Resources/AppIcon/AppIconMono.png"

/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" \
  -c "Add :CFBundleDisplayName string $APP_NAME" \
  -c 'Add :CFBundleIdentifier string com.codexmeter.macos' \
  -c "Add :CFBundleVersion string $BUILD_NUMBER" \
  -c "Add :CFBundleShortVersionString string $VERSION" \
  -c 'Add :CFBundleIconFile string AppIcon.icns' \
  -c 'Add :CFBundleExecutable string CodexMeter' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :LSApplicationCategoryType string public.app-category.developer-tools' \
  -c 'Add :LSMinimumSystemVersion string 14.0' \
  -c 'Add :NSHighResolutionCapable bool true' \
  "$CONTENTS/Info.plist"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" "$APP"
else
  codesign --force --deep --sign - "$APP"
  print -u2 "warning: DEVELOPER_ID_APPLICATION 未设置，已使用临时签名，不能作为无 Gatekeeper 警告的正式发行版。"
fi

echo "$APP"
