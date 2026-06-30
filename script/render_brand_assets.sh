#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND_DIR="$ROOT_DIR/Resources/Brand"
SVG="$BRAND_DIR/MenuBarLogo.svg"

qlmanage -t -s 1024 -o "$BRAND_DIR" "$SVG" >/dev/null 2>&1
mv -f "$BRAND_DIR/MenuBarLogo.svg.png" "$BRAND_DIR/AppIcon-1024.png"
cp "$BRAND_DIR/AppIcon-1024.png" "$BRAND_DIR/MenuBarLogo.png"

ICONSET="$BRAND_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for dimension in 16 32 128 256 512; do
  sips -z "$dimension" "$dimension" "$BRAND_DIR/AppIcon-1024.png" --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
  double=$((dimension * 2))
  sips -z "$double" "$double" "$BRAND_DIR/AppIcon-1024.png" --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BRAND_DIR/AppIcon.icns"
rm -rf "$ICONSET"

echo "Rendered vector brand assets from $SVG"
