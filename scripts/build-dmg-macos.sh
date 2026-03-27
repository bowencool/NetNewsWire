#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/NetNewsWire.xcodeproj"
SCHEME="NetNewsWire"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="NetNewsWire.app"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build/macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
DMG_NAME="NetNewsWire.dmg"
DMG_PATH="${DMG_PATH:-$BUILD_ROOT/$DMG_NAME}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --configuration <name>   Xcode build configuration (default: Release).
  --build-root <path>      Root directory for derived data and output.
  --dmg-path <path>        Output path for the .dmg file.
  -h, --help               Show this help.

Examples:
  $(basename "$0")
  $(basename "$0") --configuration Debug
  $(basename "$0") --dmg-path ~/Desktop/NetNewsWire.dmg
EOF
}

fail() {
  echo "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="${2:-}"
      [[ -n "$CONFIGURATION" ]] || fail "Missing value for --configuration"
      shift 2
      ;;
    --build-root)
      BUILD_ROOT="${2:-}"
      [[ -n "$BUILD_ROOT" ]] || fail "Missing value for --build-root"
      DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
      DMG_PATH="$BUILD_ROOT/$DMG_NAME"
      shift 2
      ;;
    --dmg-path)
      DMG_PATH="${2:-}"
      [[ -n "$DMG_PATH" ]] || fail "Missing value for --dmg-path"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

# Re-evaluate paths that depend on CONFIGURATION after arg parsing
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"

mkdir -p "$BUILD_ROOT" "$DERIVED_DATA_PATH"

echo "==> Building $APP_NAME (configuration: $CONFIGURATION) ..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  build

[[ -d "$BUILT_APP_PATH" ]] || fail "Build finished but app not found: $BUILT_APP_PATH"

STAGING_DIR="$(mktemp -d "$BUILD_ROOT/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$BUILT_APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"

echo "==> Creating DMG at $DMG_PATH ..."
hdiutil create \
  -volname "NetNewsWire" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Done"
echo "DMG: $DMG_PATH"
