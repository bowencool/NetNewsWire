#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/NetNewsWire.xcodeproj"
SCHEME="NetNewsWire-iOS"
APP_NAME="NetNewsWire.app"

CONFIGURATION=""
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build/iOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
SOURCE_PACKAGES_DIR="${SOURCE_PACKAGES_DIR:-$BUILD_ROOT/SourcePackages}"
CACHE_ROOT="${CACHE_ROOT:-$BUILD_ROOT/Caches}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/NetNewsWire-iOS.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_ROOT/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$BUILD_ROOT/ExportOptions.plist}"
ALLOW_PROVISIONING_UPDATES=1
ALLOW_PROVISIONING_DEVICE_REGISTRATION=1

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Archive the iOS app and export an .ipa file.

Options:
  --configuration <name>   Xcode build configuration.
                           Default: Debug.
  --build-root <path>      Root directory for derived data, archive, export.
  --archive-path <path>    Archive output path.
  --export-path <path>     Export directory.
  --derived-data <path>    DerivedData location.
  --no-provisioning-updates
                           Skip xcodebuild provisioning update flags.
  -h, --help               Show this help.

Examples:
  $(basename "$0")
  $(basename "$0") --configuration Release
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
  rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
  mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

  echo "==> Archiving $APP_NAME ..."
  xcodebuild \
    "${XCODEBUILD_ARGS[@]}" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    archive

  echo "==> Packaging IPA from archive ..."
  local payload_dir="$EXPORT_PATH/Payload"
  local app_path="$ARCHIVE_PATH/Products/Applications/$APP_NAME"

  [[ -d "$app_path" ]] || fail "Archived app not found at $app_path"

  mkdir -p "$payload_dir"
  cp -R "$app_path" "$payload_dir/"

  IPA_PATH="$EXPORT_PATH/NetNewsWire.ipa"
  (cd "$EXPORT_PATH" && zip -r -q "NetNewsWire.ipa" Payload)
  rm -rf "$payload_dir"

  [[ -f "$IPA_PATH" ]] || fail "Failed to create IPA at $IPA_PATH"

  echo "==> Done"
  echo "IPA: $IPA_PATH"
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
export_ipa
