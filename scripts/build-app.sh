#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP_NAME="归一"
DISPLAY_NAME="归一"
VERSION="${APP_VERSION:-2.0.1}"
BUILD_NUMBER="${APP_BUILD:-13}"
ARM_SCRATCH="$ROOT/.build/release-arm64"
X86_SCRATCH="$ROOT/.build/release-x86_64"

swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "$ARM_SCRATCH"
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$X86_SCRATCH"

ARM_BIN_DIR="$(swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "$ARM_SCRATCH" --show-bin-path)"
X86_BIN_DIR="$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$X86_SCRATCH" --show-bin-path)"

APP="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP/Contents"
rm -rf "$ROOT/dist/大同.app"
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
cp "$ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" \
  -c "Set :CFBundleDisplayName $DISPLAY_NAME" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  -c "Set :CFBundleShortVersionString $VERSION" \
  "$CONTENTS/Info.plist"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" "$APP"
else
  codesign --force --deep --sign - "$APP"
  print -u2 "warning: DEVELOPER_ID_APPLICATION 未设置，已使用临时签名，不能作为无 Gatekeeper 警告的正式发行版。"
fi

echo "$APP"
