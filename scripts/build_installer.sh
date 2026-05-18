#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${ROOT}/FinderX.xcodeproj"
SCHEME="FinderX"
CONFIGURATION="Release"
DERIVED_DATA="${ROOT}/.build/InstallerDerivedData"
TEST_DERIVED_DATA="${ROOT}/.build/TestDerivedData"
STAGING_DIR="${ROOT}/.build/installer-staging"
OUTPUT_DIR="${ROOT}/dist"
SIGNING_IDENTITY="-"
RUN_TESTS=1
REGENERATE_PROJECT=0
BUILD_NATIVE_ARCH=1

APP_ENTITLEMENTS="${ROOT}/FinderX/Resources/FinderX.entitlements"
EXTENSION_ENTITLEMENTS="${ROOT}/FinderXFinderExtension/Resources/FinderXFinderExtension.entitlements"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

usage() {
  cat <<USAGE
Usage: $0 [options]

Builds a shareable FinderX DMG installer.

Options:
  --skip-tests                  Do not run the test suite before packaging.
  --configuration NAME          Build configuration. Default: Release.
  --derived-data PATH           DerivedData path. Default: .build/InstallerDerivedData.
  --output-dir PATH             Output directory. Default: dist.
  --signing-identity IDENTITY   Code signing identity. Default: - (ad-hoc).
  --regenerate-project          Run scripts/generate_xcodeproj.rb before building.
  --universal                   Build default Xcode architectures instead of the current Mac architecture.
  -h, --help                    Show this help.

Notes:
  The default ad-hoc signed DMG is suitable for internal sharing. For public
  distribution, pass a Developer ID Application identity and notarize the DMG.
  The default build uses the current Mac architecture so it matches the bundled
  Homebrew cwebp helper.
USAGE
}

log() {
  printf '\n==> %s\n' "$1"
}

die() {
  echo "error: $*" >&2
  exit 1
}

codesign_timestamp_args=()

configure_codesign_args() {
  codesign_timestamp_args=()
  if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    codesign_timestamp_args+=(--timestamp=none)
  fi
}

sign_path() {
  local path="$1"
  shift
  codesign --force --sign "${SIGNING_IDENTITY}" "${codesign_timestamp_args[@]}" "$@" "${path}"
}

embed_webp_helper() {
  local app_path="$1"
  local cwebp="/opt/homebrew/bin/cwebp"
  if [[ ! -x "${cwebp}" ]]; then
    die "cwebp is required for WebP output but was not found at ${cwebp}. Run: brew install webp"
  fi

  local webp_root="${app_path}/Contents/Resources/cwebp"
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

  local lib
  for lib in "${libs[@]}"; do
    [[ -f "${lib}" ]] || die "required WebP dependency is missing: ${lib}"
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

  sign_path "${lib_dir}"/*.dylib
  sign_path "${bin_dir}/cwebp"
}

read_bundle_value() {
  local app_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${app_path}/Contents/Info.plist"
}

assert_helper_architecture() {
  local helper_path="$1"
  local expected_arch="$2"
  local helper_archs
  helper_archs="$(lipo -archs "${helper_path}")"
  if ! grep -qw "${expected_arch}" <<<"${helper_archs}"; then
    die "bundled cwebp architectures (${helper_archs}) do not include expected app architecture (${expected_arch})"
  fi
}

create_install_readme() {
  local path="$1"
  local version="$2"
  cat > "${path}" <<README
FinderX ${version}

Install:
1. Drag FinderX.app into Applications.
2. Launch FinderX once.
3. Enable the Finder extension if macOS asks:
   System Settings > Privacy & Security > Extensions > Finder Extensions > FinderX.
4. Restart Finder if the contextual menu does not appear immediately.

Usage:
- Right-click a JPEG, PNG, or WebP file in Downloads, Desktop, Pictures, or iCloud Drive.
- Choose "Compress with FinderX".

Signing:
- This build was packaged by scripts/build_installer.sh.
- If it was ad-hoc signed, macOS may require right-click > Open on first launch.
- For wider distribution, rebuild with a Developer ID Application identity and notarize the DMG.
README
}

refresh_services_cache_without_build_products() {
  local app_path="$1"
  local test_app_path="${TEST_DERIVED_DATA}/Build/Products/Debug/FinderX.app"
  local staging_app_path="${STAGING_DIR}/FinderX.app"
  local stale_app

  for stale_app in "${app_path}" "${test_app_path}" "${staging_app_path}"; do
    if [[ -d "${stale_app}" ]]; then
      "${LSREGISTER}" -u "${stale_app}" >/dev/null 2>&1 || true
    fi
  done

  "${PBS}" -flush >/dev/null 2>&1 || true
  "${PBS}" -update >/dev/null 2>&1 || true
}

remove_local_app_products() {
  local app_path="$1"
  local test_app_path="${TEST_DERIVED_DATA}/Build/Products/Debug/FinderX.app"
  local staging_app_path="${STAGING_DIR}/FinderX.app"

  rm -rf "${app_path}" "${test_app_path}" "${staging_app_path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --configuration)
      [[ $# -ge 2 ]] || die "--configuration requires a value"
      CONFIGURATION="$2"
      shift 2
      ;;
    --derived-data)
      [[ $# -ge 2 ]] || die "--derived-data requires a value"
      DERIVED_DATA="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --signing-identity)
      [[ $# -ge 2 ]] || die "--signing-identity requires a value"
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --regenerate-project)
      REGENERATE_PROJECT=1
      shift
      ;;
    --universal)
      BUILD_NATIVE_ARCH=0
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

configure_codesign_args

cd "${ROOT}"

if [[ "${REGENERATE_PROJECT}" == "1" ]]; then
  log "Generating Xcode project"
  ruby scripts/generate_xcodeproj.rb
fi

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

log "Building ${CONFIGURATION} app"
build_settings=()
PACKAGE_ARCH="universal"
if [[ "${BUILD_NATIVE_ARCH}" == "1" ]]; then
  PACKAGE_ARCH="$(uname -m)"
  build_settings+=(ONLY_ACTIVE_ARCH=YES ARCHS="${PACKAGE_ARCH}")
fi

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination platform=macOS \
  -derivedDataPath "${DERIVED_DATA}" \
  "${build_settings[@]}" \
  build

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/FinderX.app"
[[ -d "${APP_PATH}" ]] || die "built app was not found at ${APP_PATH}"

log "Embedding bundled WebP encoder"
embed_webp_helper "${APP_PATH}"
if [[ "${BUILD_NATIVE_ARCH}" == "1" ]]; then
  assert_helper_architecture "${APP_PATH}/Contents/Resources/cwebp/bin/cwebp" "${PACKAGE_ARCH}"
fi

log "Signing app bundle"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/FinderXFinderExtension.appex"
[[ -d "${EXTENSION_PATH}" ]] || die "Finder extension was not found at ${EXTENSION_PATH}"
sign_path "${EXTENSION_PATH}" --entitlements "${EXTENSION_ENTITLEMENTS}"
sign_path "${APP_PATH}" --entitlements "${APP_ENTITLEMENTS}"

log "Verifying signature"
codesign --verify --deep --strict "${APP_PATH}"
codesign -d --entitlements :- "${APP_PATH}" 2>/dev/null | grep -q "com.apple.security.app-sandbox"
codesign -d --entitlements :- "${EXTENSION_PATH}" 2>/dev/null | grep -q "com.apple.security.app-sandbox"

VERSION="$(read_bundle_value "${APP_PATH}" CFBundleShortVersionString)"
BUILD="$(read_bundle_value "${APP_PATH}" CFBundleVersion)"
DMG_BASENAME="FinderX-${VERSION}-${BUILD}-${PACKAGE_ARCH}"
DMG_PATH="${OUTPUT_DIR}/${DMG_BASENAME}.dmg"

log "Staging installer"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" "${OUTPUT_DIR}"
ditto "${APP_PATH}" "${STAGING_DIR}/FinderX.app"
ln -s /Applications "${STAGING_DIR}/Applications"
create_install_readme "${STAGING_DIR}/README_INSTALL.txt" "${VERSION} (${BUILD})"

log "Creating DMG"
rm -f "${DMG_PATH}" "${DMG_PATH}.sha256"
hdiutil create \
  -volname "FinderX ${VERSION}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"

log "Refreshing local Services cache"
refresh_services_cache_without_build_products "${APP_PATH}"

log "Removing local app products"
remove_local_app_products "${APP_PATH}"

cat <<INFO

FinderX installer is ready.
dmg=${DMG_PATH}
sha256=${DMG_PATH}.sha256
signing_identity=${SIGNING_IDENTITY}
INFO
