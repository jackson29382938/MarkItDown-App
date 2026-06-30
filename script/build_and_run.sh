#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MarkItDown"
BUNDLE_ID="app.markitdown.menubar"
MIN_SYSTEM_VERSION="14.0"
MARKITDOWN_VERSION="${MARKITDOWN_VERSION:-0.1.6}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
MARKITDOWN_REQUIREMENT="markitdown[docx,pptx,xlsx,xls,pdf,outlook]==${MARKITDOWN_VERSION}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENGINE_CACHE="$ROOT_DIR/.build/engine-cache/$MARKITDOWN_VERSION"
ENGINE_DESTINATION="$APP_RESOURCES/Engine"

usage() {
  echo "usage: $0 [run|--build-only|--sign|--notarize|--debug|--logs|--telemetry|--verify]" >&2
  echo "  Signing: set CODESIGN_IDENTITY to sign with a Developer ID certificate." >&2
  echo "  Notarize: set NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_APP_PASSWORD, and CODESIGN_IDENTITY." >&2
}

require_uv() {
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv is required to stage the bundled Python engine. Install uv and rerun." >&2
    exit 1
  fi
}

python_source_root() {
  require_uv
  uv python install "$PYTHON_VERSION" >/dev/null
  local python_path
  python_path="$(uv python find "$PYTHON_VERSION")"
  cd "$(dirname "$python_path")/.." && pwd
}

write_manifest() {
  local destination="$1"
  local install_kind="$2"
  local created_at
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cat >"$destination/manifest.json" <<JSON
{
  "markitdownVersion": "$MARKITDOWN_VERSION",
  "pythonVersion": "$PYTHON_VERSION",
  "createdAt": "$created_at",
  "installKind": "$install_kind"
}
JSON
}

bootstrap_engine_cache() {
  local manifest="$ENGINE_CACHE/manifest.json"
  if [[ -f "$manifest" ]] && grep -q "\"markitdownVersion\": \"$MARKITDOWN_VERSION\"" "$manifest"; then
    return
  fi

  local source_python
  source_python="$(python_source_root)"

  rm -rf "$ENGINE_CACHE"
  mkdir -p "$ENGINE_CACHE/site-packages"
  cp -R "$source_python" "$ENGINE_CACHE/python"

  uv pip install \
    --target "$ENGINE_CACHE/site-packages" \
    --python-version "$PYTHON_VERSION" \
    --python-platform aarch64-apple-darwin \
    --compile-bytecode \
    "$MARKITDOWN_REQUIREMENT"

  write_manifest "$ENGINE_CACHE" "bundled"
}

stage_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true

  bash "$ROOT_DIR/script/render_brand_assets.sh"
  bash "$ROOT_DIR/script/generate_quick_action_workflow.sh"

  swift build
  local build_binary
  build_binary="$(swift build --show-bin-path)/$APP_NAME"

  bootstrap_engine_cache

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  cp -R "$ROOT_DIR/Resources/." "$APP_RESOURCES/"
  cp "$ROOT_DIR/Resources/Brand/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
  rm -rf "$ENGINE_DESTINATION"
  cp -R "$ENGINE_CACHE" "$ENGINE_DESTINATION"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>markitdown</string>
      </array>
    </dict>
  </array>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>Convert to Markdown</string>
      </dict>
      <key>NSMessage</key>
      <string>convertToMarkdown</string>
      <key>NSPortName</key>
      <string>$APP_NAME</string>
      <key>NSSendTypes</key>
      <array>
        <string>NSFilenamesPboardType</string>
        <string>public.file-url</string>
      </array>
      <key>NSRequiredContext</key>
      <dict>
        <key>NSApplicationIdentifier</key>
        <string>com.apple.finder</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

  sign_app_bundle
}

sign_app_bundle() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "Signing app with identity: $CODESIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BINARY"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    return
  fi

  if ! codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "Applying ad-hoc signature for local development"
    codesign --force --deep -s - "$APP_BUNDLE"
  fi
}

notarize_app_bundle() {
  if [[ -z "${NOTARY_APPLE_ID:-}" || -z "${NOTARY_TEAM_ID:-}" || -z "${NOTARY_APP_PASSWORD:-}" || -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "Skipping notarization. Set NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_APP_PASSWORD, and CODESIGN_IDENTITY." >&2
    return 1
  fi

  local archive_path="$DIST_DIR/MarkItDown.zip"
  rm -f "$archive_path"
  ditto -c -k --keepParent "$APP_BUNDLE" "$archive_path"
  xcrun notarytool submit "$archive_path" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

cd "$ROOT_DIR"

case "$MODE" in
  run)
    stage_app
    open_app
    ;;
  --build-only|build-only)
    stage_app
    ;;
  --sign|sign)
    stage_app
    ;;
  --notarize|notarize)
    stage_app
    notarize_app_bundle
    ;;
  --debug|debug)
    stage_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stage_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stage_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stage_app
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
