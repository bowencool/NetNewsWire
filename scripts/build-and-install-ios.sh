#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/NetNewsWire.xcodeproj"
SCHEME="NetNewsWire-iOS"
APP_NAME="NetNewsWire.app"

MODE="ipa"
CONFIGURATION=""
DEVICE_QUERY=""
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build/iOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
SOURCE_PACKAGES_DIR="${SOURCE_PACKAGES_DIR:-$BUILD_ROOT/SourcePackages}"
CACHE_ROOT="${CACHE_ROOT:-$BUILD_ROOT/Caches}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/NetNewsWire-iOS.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_ROOT/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$BUILD_ROOT/ExportOptions.plist}"
ALLOW_PROVISIONING_UPDATES=1
ALLOW_PROVISIONING_DEVICE_REGISTRATION=1
LAUNCH_AFTER_INSTALL=1

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [ipa|install] [options]

Modes:
  ipa                 Archive the iOS app and export an .ipa file.
  install             Build the iOS app and install it on a connected iPhone.

Options:
  --configuration <name>   Xcode build configuration.
                           Default: Debug.
  --device <value>         Device name, UDID, or devicectl identifier.
                           Only used by install mode.
  --build-root <path>      Root directory for derived data, archive, export.
  --archive-path <path>    Archive output path for ipa mode.
  --export-path <path>     Export directory for ipa mode.
  --derived-data <path>    DerivedData location.
  --no-launch              Install mode only: don't launch after install.
  --no-provisioning-updates
                           Skip xcodebuild provisioning update flags.
  -h, --help               Show this help.

Examples:
  $(basename "$0") ipa
  $(basename "$0") install
  $(basename "$0") install --device "Bowen’s iPhone"
EOF
}

fail() {
  echo "$1" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required tool: $1"
}

prepare_build_dirs() {
  require_tool xcodebuild
  require_tool xcrun

  mkdir -p \
    "$BUILD_ROOT" \
    "$DERIVED_DATA_PATH" \
    "$SOURCE_PACKAGES_DIR" \
    "$CACHE_ROOT/clang/ModuleCache" \
    "$CACHE_ROOT/org.swift.swiftpm/ModuleCache" \
    "$BUILD_ROOT/tmp"

  export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang/ModuleCache"
  export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/org.swift.swiftpm/ModuleCache"
  export TMPDIR="$BUILD_ROOT/tmp/"
}

resolve_device() {
  require_tool python3

  local json_path
  json_path="$(mktemp "$BUILD_ROOT/devicectl-devices.XXXXXX.json")"
  xcrun devicectl list devices --json-output "$json_path" >/dev/null

  local result
  if ! result="$(python3 - "$json_path" "$DEVICE_QUERY" <<'PY'
import json
import sys

path = sys.argv[1]
query = sys.argv[2].strip().casefold()

with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

devices = payload.get("result", {}).get("devices", [])
candidates = []
for device in devices:
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    properties = device.get("deviceProperties", {})
    if hardware.get("platform") != "iOS":
        continue
    if hardware.get("reality") != "physical":
        continue
    if connection.get("pairingState") != "paired":
        continue
    candidates.append(
        {
            "name": properties.get("name", ""),
            "udid": hardware.get("udid", ""),
            "identifier": device.get("identifier", ""),
        }
    )

if query:
    exact = [
        device
        for device in candidates
        if query in {
            device["name"].casefold(),
            device["udid"].casefold(),
            device["identifier"].casefold(),
        }
    ]
    if exact:
        candidates = exact
    else:
        candidates = [
            device
            for device in candidates
            if query in device["name"].casefold()
            or query in device["udid"].casefold()
            or query in device["identifier"].casefold()
        ]

if len(candidates) == 1:
    device = candidates[0]
    print(f"{device['name']}\t{device['udid']}\t{device['identifier']}")
    sys.exit(0)

if not candidates:
    sys.exit(2)

for device in candidates:
    print(f"{device['name']}\t{device['udid']}\t{device['identifier']}")
sys.exit(3)
PY
  )"; then
    local status=$?
    rm -f "$json_path"
    if [[ $status -eq 2 ]]; then
      if [[ -n "$DEVICE_QUERY" ]]; then
        fail "No paired iPhone matched device query: $DEVICE_QUERY"
      fi
      fail "No paired iPhone found. Connect your iPhone, trust this Mac, and enable Developer Mode."
    fi
    if [[ $status -eq 3 ]]; then
      echo "Multiple paired iPhones matched. Re-run with --device and one of:" >&2
      while IFS=$'\t' read -r name udid identifier; do
        echo "  $name | UDID: $udid | Identifier: $identifier" >&2
      done <<<"$result"
      exit 1
    fi
    exit "$status"
  fi

  rm -f "$json_path"

  IFS=$'\t' read -r DEVICE_NAME DEVICE_UDID DEVICE_IDENTIFIER <<<"$result"
  export DEVICE_NAME DEVICE_UDID DEVICE_IDENTIFIER
}

build_common_args() {
  XCODEBUILD_ARGS=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR"
  )

  if [[ $ALLOW_PROVISIONING_UPDATES -eq 1 ]]; then
    XCODEBUILD_ARGS+=(-allowProvisioningUpdates)
  fi

  if [[ $ALLOW_PROVISIONING_DEVICE_REGISTRATION -eq 1 ]]; then
    XCODEBUILD_ARGS+=(-allowProvisioningDeviceRegistration)
  fi
}

export_ipa() {
  local export_args=()

  rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
  mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

  cat >"$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>compileBitcode</key>
  <false/>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>debugging</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
EOF

  echo "==> Archiving $APP_NAME ..."
  xcodebuild \
    "${XCODEBUILD_ARGS[@]}" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    archive

  echo "==> Exporting IPA ..."
  if [[ $ALLOW_PROVISIONING_UPDATES -eq 1 ]]; then
    export_args+=(-allowProvisioningUpdates)
  fi

  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    "${export_args[@]}"

  IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -print -quit)"
  [[ -n "${IPA_PATH:-}" ]] || fail "Export finished but no .ipa was found in $EXPORT_PATH"

  echo "==> Done"
  echo "IPA: $IPA_PATH"
}

install_on_device() {
  resolve_device

  echo "==> Using device: $DEVICE_NAME"
  echo "    UDID: $DEVICE_UDID"

  echo "==> Building $APP_NAME ..."
  xcodebuild \
    "${XCODEBUILD_ARGS[@]}" \
    -destination "id=$DEVICE_UDID" \
    build

  APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/$APP_NAME"
  [[ -d "$APP_PATH" ]] || fail "Build finished but app not found: $APP_PATH"

  echo "==> Installing to $DEVICE_NAME ..."
  xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"

  BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"

  if [[ $LAUNCH_AFTER_INSTALL -eq 1 ]]; then
    echo "==> Launching $BUNDLE_IDENTIFIER ..."
    xcrun devicectl device process launch --terminate-existing --device "$DEVICE_UDID" "$BUNDLE_IDENTIFIER"
  fi

  echo "==> Done"
  echo "Installed app: $APP_PATH"
  echo "Bundle ID: $BUNDLE_IDENTIFIER"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    ipa|install)
      MODE="$1"
      shift
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      [[ -n "$CONFIGURATION" ]] || fail "Missing value for --configuration"
      shift 2
      ;;
    --device)
      DEVICE_QUERY="${2:-}"
      [[ -n "$DEVICE_QUERY" ]] || fail "Missing value for --device"
      shift 2
      ;;
    --build-root)
      BUILD_ROOT="${2:-}"
      [[ -n "$BUILD_ROOT" ]] || fail "Missing value for --build-root"
      DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
      SOURCE_PACKAGES_DIR="$BUILD_ROOT/SourcePackages"
      CACHE_ROOT="$BUILD_ROOT/Caches"
      ARCHIVE_PATH="$BUILD_ROOT/NetNewsWire-iOS.xcarchive"
      EXPORT_PATH="$BUILD_ROOT/export"
      EXPORT_OPTIONS_PLIST="$BUILD_ROOT/ExportOptions.plist"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="${2:-}"
      [[ -n "$ARCHIVE_PATH" ]] || fail "Missing value for --archive-path"
      shift 2
      ;;
    --export-path)
      EXPORT_PATH="${2:-}"
      [[ -n "$EXPORT_PATH" ]] || fail "Missing value for --export-path"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_PATH="${2:-}"
      [[ -n "$DERIVED_DATA_PATH" ]] || fail "Missing value for --derived-data"
      shift 2
      ;;
    --no-launch)
      LAUNCH_AFTER_INSTALL=0
      shift
      ;;
    --no-provisioning-updates)
      ALLOW_PROVISIONING_UPDATES=0
      ALLOW_PROVISIONING_DEVICE_REGISTRATION=0
      shift
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

CONFIGURATION="${CONFIGURATION:-Debug}"

prepare_build_dirs
build_common_args

if [[ "$MODE" == "ipa" ]]; then
  export_ipa
else
  install_on_device
fi
