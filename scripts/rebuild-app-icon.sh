#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
ICON_DIR="$ROOT/Sources/CodexMeter/Resources/AppIcon"
ICONSET="$ICON_DIR/AppIcon.iconset"

swift "$ROOT/scripts/remove-icon-canvas.swift" \
  "$ICON_DIR/AppIconDefault.png" \
  "$ICON_DIR/AppIconDark.png" \
  "$ICON_DIR/AppIconMono.png"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_DIR/AppIconDefault.png" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_DIR/AppIconDefault.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICON_DIR/AppIcon.icns"
rm -rf "$ICONSET"
