#!/bin/bash
set -euo pipefail

PROJECT_PATH="NetNewsWire.xcodeproj"
SCHEME="NetNewsWire"
CONFIGURATION="Debug"
DESTINATION="platform=macOS,arch=arm64"
DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData/NetNewsWire-LocalBuild"
APP_NAME="NetNewsWire.app"
APP_PROCESS_NAME="${APP_NAME%.app}"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"

echo "==> Stopping running $APP_PROCESS_NAME instances ..."
pkill -x "$APP_PROCESS_NAME" 2>/dev/null || true

echo "==> Building $APP_NAME ..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "Build finished but app not found: $BUILT_APP_PATH"
  exit 1
fi

echo "==> Installing to $INSTALL_PATH ..."
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP_PATH" "$INSTALL_PATH"

echo "==> Done"
echo "Installed app: $INSTALL_PATH"
