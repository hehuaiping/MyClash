#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${MYCLASH_APP_NAME:-MyClash}"
BUNDLE_ID="${MYCLASH_BUNDLE_ID:-com.myclash.desktop}"
VERSION="${MYCLASH_VERSION:-0.3.0}"
BUILD_NUMBER="${MYCLASH_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${MYCLASH_SIGN_IDENTITY:-}"
AD_HOC_SIGN="${MYCLASH_AD_HOC_SIGN:-1}"
NOTARIZE="${MYCLASH_NOTARIZE:-0}"
NOTARY_PROFILE="${MYCLASH_NOTARY_PROFILE:-}"

BUILD_DIR="${REPO_ROOT}/.build"
SWIFTPM_CACHE="${BUILD_DIR}/swiftpm-cache"
MODULE_CACHE="${BUILD_DIR}/module-cache"
RELEASE_DIR="${BUILD_DIR}/release"
DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
HELPERS_DIR="${CONTENTS_DIR}/Library/Helpers"
INFO_PLIST="${CONTENTS_DIR}/Info.plist"
ENTITLEMENTS="${REPO_ROOT}/Packaging/MyClash.entitlements"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-${BUILD_NUMBER}.zip"
CORE_RESOURCE_BUNDLE="MyClash_MyClashCore.bundle"
APP_ICON="${REPO_ROOT}/Packaging/MyClash.icns"

log() {
  printf '[MyClash package] %s\n' "$1"
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

build_release() {
  log "building Swift Package release executables"
  env CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" \
    swift build -c release --cache-path "${SWIFTPM_CACHE}" --disable-sandbox
}

assemble_bundle() {
  log "assembling ${APP_BUNDLE}"
  rm -rf "${APP_BUNDLE}"
  mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${HELPERS_DIR}"

  cp "${RELEASE_DIR}/myclash-app" "${MACOS_DIR}/${APP_NAME}"
  cp "${RELEASE_DIR}/myclash" "${HELPERS_DIR}/myclash"
  cp "${REPO_ROOT}/Packaging/Info.plist" "${INFO_PLIST}"
  cp -R "${RELEASE_DIR}/${CORE_RESOURCE_BUNDLE}" "${RESOURCES_DIR}/${CORE_RESOURCE_BUNDLE}"
  cp "${APP_ICON}" "${RESOURCES_DIR}/MyClash.icns"

  chmod 755 "${MACOS_DIR}/${APP_NAME}" "${HELPERS_DIR}/myclash"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${INFO_PLIST}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${INFO_PLIST}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${INFO_PLIST}"
}

sign_path() {
  local path="$1"
  local identity="$2"

  codesign --force \
    --options runtime \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${identity}" \
    "${path}"
}

sign_bundle() {
  if [[ -n "${SIGN_IDENTITY}" ]]; then
    log "signing app bundle with Developer ID identity"
    sign_path "${HELPERS_DIR}/myclash" "${SIGN_IDENTITY}"
    sign_path "${MACOS_DIR}/${APP_NAME}" "${SIGN_IDENTITY}"
    sign_path "${APP_BUNDLE}" "${SIGN_IDENTITY}"
  elif [[ "${AD_HOC_SIGN}" == "1" ]]; then
    log "ad-hoc signing app bundle"
    sign_path "${HELPERS_DIR}/myclash" "-"
    sign_path "${MACOS_DIR}/${APP_NAME}" "-"
    sign_path "${APP_BUNDLE}" "-"
  else
    log "signature skipped"
  fi
}

verify_bundle() {
  if [[ -n "${SIGN_IDENTITY}" || "${AD_HOC_SIGN}" == "1" ]]; then
    log "verifying code signature"
    codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
    codesign --display --verbose=2 "${APP_BUNDLE}"
  fi
}

make_zip() {
  local zip_path="$1"
  rm -f "${zip_path}"
  log "creating ${zip_path}"
  (cd "${DIST_DIR}" && ditto -c -k --keepParent "${APP_NAME}.app" "${zip_path}")
}

notarize_bundle() {
  if [[ "${NOTARIZE}" != "1" ]]; then
    return
  fi

  if [[ -z "${SIGN_IDENTITY}" ]]; then
    printf 'error: notarization requires MYCLASH_SIGN_IDENTITY.\n' >&2
    exit 1
  fi
  if [[ -z "${NOTARY_PROFILE}" ]]; then
    printf 'error: notarization requires MYCLASH_NOTARY_PROFILE.\n' >&2
    exit 1
  fi

  require_tool xcrun
  make_zip "${ZIP_PATH}"
  log "submitting archive to Apple notarization"
  xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
  log "stapling notarization ticket"
  xcrun stapler staple "${APP_BUNDLE}"
}

main() {
  require_tool swift
  require_tool codesign
  require_tool ditto
  validate_version
  validate_build_number

  cd "${REPO_ROOT}"
  mkdir -p "${DIST_DIR}" "${SWIFTPM_CACHE}" "${MODULE_CACHE}"

  build_release
  assemble_bundle
  sign_bundle
  verify_bundle
  notarize_bundle
  make_zip "${ZIP_PATH}"

  log "done: ${APP_BUNDLE}"
  log "archive: ${ZIP_PATH}"
}

main "$@"
