#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${ROOT}/FinderX.xcodeproj"
SCHEME="FinderX"
APP_DERIVED_DATA="${ROOT}/.build/DerivedData"
TEST_DERIVED_DATA="${ROOT}/.build/TestDerivedData"
APP_PATH="${APP_DERIVED_DATA}/Build/Products/Debug/FinderX.app"
TEST_APP_PATH="${TEST_DERIVED_DATA}/Build/Products/Debug/FinderX.app"
APP_ENTITLEMENTS="${ROOT}/FinderX/Resources/FinderX.entitlements"
EXTENSION_ID="dev.finderx.FinderX.FinderExtension"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

RUN_TESTS=1
RESTART_FINDER=1

usage() {
  cat <<USAGE
Usage: $0 [--skip-tests] [--no-restart-finder]

Builds a Finder-loadable debug app without letting unsigned test products
overwrite the locally signed Finder Sync Extension bundle.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --no-restart-finder)
      RESTART_FINDER=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

log() {
  printf '\n==> %s\n' "$1"
}

embed_webp_helper() {
  local cwebp="/opt/homebrew/bin/cwebp"
  if [[ ! -x "${cwebp}" ]]; then
    echo "cwebp is required for WebP output but was not found at ${cwebp}" >&2
    exit 1
  fi

  local webp_root="${APP_PATH}/Contents/Resources/cwebp"
  local bin_dir="${webp_root}/bin"
  local lib_dir="${webp_root}/lib"
  rm -rf "${webp_root}"
  mkdir -p "${bin_dir}" "${lib_dir}"

  cp -L "${cwebp}" "${bin_dir}/cwebp"
  chmod 755 "${bin_dir}/cwebp"

  local libs=(
    "/opt/homebrew/lib/libwebpdemux.2.dylib"
    "/opt/homebrew/lib/libwebp.7.dylib"
    "/opt/homebrew/lib/libsharpyuv.0.dylib"
    "/opt/homebrew/opt/libpng/lib/libpng16.16.dylib"
    "/opt/homebrew/opt/jpeg-turbo/lib/libjpeg.8.dylib"
    "/opt/homebrew/opt/libtiff/lib/libtiff.6.dylib"
    "/opt/homebrew/opt/zstd/lib/libzstd.1.dylib"
    "/opt/homebrew/opt/xz/lib/liblzma.5.dylib"
  )

  for lib in "${libs[@]}"; do
    cp -L "${lib}" "${lib_dir}/$(basename "${lib}")"
    chmod 644 "${lib_dir}/$(basename "${lib}")"
  done

  install_name_tool \
    -change /opt/homebrew/opt/libpng/lib/libpng16.16.dylib @loader_path/../lib/libpng16.16.dylib \
    -change /opt/homebrew/opt/jpeg-turbo/lib/libjpeg.8.dylib @loader_path/../lib/libjpeg.8.dylib \
    -change /opt/homebrew/opt/libtiff/lib/libtiff.6.dylib @loader_path/../lib/libtiff.6.dylib \
    "${bin_dir}/cwebp"

  install_name_tool \
    -change /opt/homebrew/opt/zstd/lib/libzstd.1.dylib @loader_path/libzstd.1.dylib \
    -change /opt/homebrew/opt/xz/lib/liblzma.5.dylib @loader_path/liblzma.5.dylib \
    -change /opt/homebrew/opt/jpeg-turbo/lib/libjpeg.8.dylib @loader_path/libjpeg.8.dylib \
    "${lib_dir}/libtiff.6.dylib"

  codesign --force --sign - --timestamp=none "${lib_dir}"/*.dylib
  codesign --force --sign - --timestamp=none "${bin_dir}/cwebp"
}

refresh_services() {
  if [[ -d "${TEST_APP_PATH}" ]]; then
    "${LSREGISTER}" -u "${TEST_APP_PATH}" >/dev/null 2>&1 || true
  fi
  "${LSREGISTER}" -f -R -trusted "${APP_PATH}" >/dev/null 2>&1 || true
  "${PBS}" -flush >/dev/null 2>&1 || true
  "${PBS}" -update >/dev/null 2>&1 || true
}

cd "${ROOT}"

log "Generating Xcode project"
ruby scripts/generate_xcodeproj.rb

if [[ "${RUN_TESTS}" == "1" ]]; then
  log "Running tests in isolated DerivedData"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -destination platform=macOS \
    -derivedDataPath "${TEST_DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    test
fi

log "Building locally signed debug app"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination platform=macOS \
  -derivedDataPath "${APP_DERIVED_DATA}" \
  build

log "Embedding bundled WebP encoder"
embed_webp_helper
codesign --force --sign - --entitlements "${APP_ENTITLEMENTS}" --timestamp=none "${APP_PATH}"

log "Verifying app entitlements"
codesign -d --entitlements :- "${APP_PATH}" 2>/dev/null | grep -q "com.apple.security.app-sandbox"
codesign -d --entitlements :- "${APP_PATH}" 2>/dev/null | grep -q "com.apple.security.files.downloads.read-write"
codesign -d --entitlements :- "${APP_PATH}/Contents/PlugIns/FinderXFinderExtension.appex" 2>/dev/null | grep -q "com.apple.security.app-sandbox"

log "Refreshing Launch Services and Finder Services"
refresh_services

log "Registering and enabling Finder Sync Extension"
pluginkit -a "${APP_PATH}"
pluginkit -e use -i "${EXTENSION_ID}"

if [[ "${RESTART_FINDER}" == "1" ]]; then
  log "Restarting Finder"
  pkill -f "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder" || true
fi

log "PluginKit status"
pluginkit -m -p com.apple.FinderSync -v | grep "${EXTENSION_ID}"

cat <<INFO

FinderX debug app is installed for Finder acceptance.
app=${APP_PATH}
extension=${EXTENSION_ID}
test_derived_data=${TEST_DERIVED_DATA}
app_derived_data=${APP_DERIVED_DATA}
INFO
