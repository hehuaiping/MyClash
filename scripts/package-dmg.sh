#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${MYCLASH_APP_NAME:-MyClash}"
VERSION="${MYCLASH_VERSION:-0.1.0}"
BUILD_NUMBER="${MYCLASH_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SKIP_APP_BUILD="${MYCLASH_SKIP_APP_BUILD:-0}"

DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_STAGING_DIR="${DIST_DIR}/dmg-${APP_NAME}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-${BUILD_NUMBER}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"

log() {
  printf '[MyClash dmg] %s\n' "$1"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required tool not found: %s\n' "$1" >&2
    exit 1
  fi
}

validate_version() {
  if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([.+-][A-Za-z0-9._-]+)?$ ]]; then
    printf 'error: invalid MYCLASH_VERSION: %s\n' "$VERSION" >&2
    exit 1
  fi
}

validate_build_number() {
  if [[ ! "$BUILD_NUMBER" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'error: invalid MYCLASH_BUILD_NUMBER: %s\n' "$BUILD_NUMBER" >&2
    exit 1
  fi
}

ensure_app_bundle() {
  if [[ "$SKIP_APP_BUILD" == "1" ]]; then
    if [[ ! -d "$APP_BUNDLE" ]]; then
      printf 'error: %s does not exist. Run scripts/package-myclash.sh first or unset MYCLASH_SKIP_APP_BUILD.\n' "$APP_BUNDLE" >&2
      exit 1
    fi
    log "using existing ${APP_BUNDLE}"
    return
  fi

  log "building app bundle with scripts/package-myclash.sh"
  "${SCRIPT_DIR}/package-myclash.sh"
}

prepare_staging_dir() {
  log "preparing ${DMG_STAGING_DIR}"
  rm -rf "$DMG_STAGING_DIR"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/${APP_NAME}.app"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
}

create_dmg() {
  rm -f "$DMG_PATH"
  log "creating ${DMG_PATH}"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
}

verify_dmg() {
  log "verifying ${DMG_PATH}"
  hdiutil verify "$DMG_PATH"
  hdiutil imageinfo "$DMG_PATH" >/dev/null
}

cleanup() {
  rm -rf "$DMG_STAGING_DIR"
}

main() {
  require_tool hdiutil
  require_tool cp
  require_tool ln
  validate_version
  validate_build_number

  cd "$REPO_ROOT"
  mkdir -p "$DIST_DIR"
  trap cleanup EXIT

  ensure_app_bundle
  prepare_staging_dir
  create_dmg
  verify_dmg

  log "done: ${DMG_PATH}"
}

main "$@"
