#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudeRadar"
APP_BUNDLE="$ROOT_DIR/.build/app/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION" --product "$APP_NAME"
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Config/ClaudeRadar-Info.plist" "$CONTENTS/Info.plist"

RESOURCE_BUNDLE="$BIN_DIR/ClaudeRadar_ClaudeRadar.bundle"
if [[ "$CONFIGURATION" == "debug" ]]; then
  if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
    exit 1
  fi
  cp -R "$RESOURCE_BUNDLE/." "$RESOURCES_DIR/"
else
  if find "$RESOURCES_DIR" -type f -print -quit | grep -q .; then
    echo "Release bundle must not contain fixture or Debug resources" >&2
    exit 1
  fi
fi

chmod +x "$MACOS_DIR/$APP_NAME"
/usr/bin/codesign --force --deep --options runtime --timestamp=none --sign - "$APP_BUNDLE"
echo "$APP_BUNDLE"
