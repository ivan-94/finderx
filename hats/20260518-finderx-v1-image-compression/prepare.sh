#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${HOME}/Downloads/FinderX-Agent-Test"
SOURCE_IMAGE="${TEST_DIR}/finderx-e2e-source.jpg"

usage() {
  echo "Usage: $0 {info|prepare|cleanup}"
}

info() {
  cat <<INFO
HAT_PREPARE_SUMMARY
mode=blank
status=not-run
repo_root=${ROOT}
test_dir=${TEST_DIR}
sample_image=${SOURCE_IMAGE}
app=.build/DerivedData/Build/Products/Debug/FinderX.app
installer=./scripts/install_debug_app.sh
cleanup=$0 cleanup
guide=./hats/20260518-finderx-v1-image-compression/guide.md
END_HAT_PREPARE_SUMMARY
INFO
}

prepare() {
  cd "${ROOT}"
  mkdir -p "${TEST_DIR}"
  ruby scripts/generate_xcodeproj.rb
  swift -module-cache-path .build/module-cache scripts/create_sample_image.swift "${SOURCE_IMAGE}" >/dev/null

  cat <<INFO
HAT_PREPARE_SUMMARY
mode=blank
status=prepared
repo_root=${ROOT}
test_dir=${TEST_DIR}
sample_image=${SOURCE_IMAGE}
app=.build/DerivedData/Build/Products/Debug/FinderX.app
installer=./scripts/install_debug_app.sh
cleanup=$0 cleanup
guide=./hats/20260518-finderx-v1-image-compression/guide.md
END_HAT_PREPARE_SUMMARY
INFO
}

cleanup() {
  rm -rf "${TEST_DIR}"
  cat <<INFO
HAT_PREPARE_SUMMARY
mode=blank
status=cleaned
test_dir=${TEST_DIR}
END_HAT_PREPARE_SUMMARY
INFO
}

case "${1:-}" in
  info) info ;;
  prepare) prepare ;;
  cleanup) cleanup ;;
  *) usage; exit 64 ;;
esac
