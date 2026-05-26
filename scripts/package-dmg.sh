#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${MYCLASH_APP_NAME:-MyClash}"
VERSION="${MYCLASH_VERSION:-0.2.0}"
BUILD_NUMBER="${MYCLASH_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SKIP_APP_BUILD="${MYCLASH_SKIP_APP_BUILD:-0}"

DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_STAGING_DIR="${DIST_DIR}/dmg-${APP_NAME}"
DMG_WORK_DIR="${DIST_DIR}/dmg-work-${APP_NAME}"
RW_DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-${BUILD_NUMBER}.rw.dmg"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-${BUILD_NUMBER}.dmg"
MOUNT_DIR="${DMG_WORK_DIR}/mount"
VOLUME_NAME="${APP_NAME} ${VERSION}"
BACKGROUND_DIR_NAME=".background"
BACKGROUND_FILE_NAME="installer-background.png"

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
  mkdir -p "$DMG_STAGING_DIR/${BACKGROUND_DIR_NAME}"
  generate_background "$DMG_STAGING_DIR/${BACKGROUND_DIR_NAME}/${BACKGROUND_FILE_NAME}"
}

generate_background() {
  local output_path="$1"
  local generator_script="${DMG_WORK_DIR}/generate-dmg-background.swift"

  mkdir -p "$DMG_WORK_DIR"
  cat >"$generator_script" <<'SWIFT'
import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let appName = CommandLine.arguments[2]
let size = NSSize(width: 640, height: 360)
let image = NSImage(size: size)

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.982, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1),
    .paragraphStyle: titleStyle
]
("Drag \(appName) to Applications" as NSString).draw(
    in: NSRect(x: 0, y: 295, width: size.width, height: 40),
    withAttributes: titleAttributes
)

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.38, green: 0.42, blue: 0.48, alpha: 1),
    .paragraphStyle: titleStyle
]
("Install by dragging the app icon into the Applications folder." as NSString).draw(
    in: NSRect(x: 0, y: 268, width: size.width, height: 24),
    withAttributes: subtitleAttributes
)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 250, y: 158))
arrow.line(to: NSPoint(x: 390, y: 158))
arrow.lineWidth = 5
NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.92, alpha: 1).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 390, y: 158))
arrowHead.line(to: NSPoint(x: 368, y: 173))
arrowHead.move(to: NSPoint(x: 390, y: 158))
arrowHead.line(to: NSPoint(x: 368, y: 143))
arrowHead.lineWidth = 5
arrowHead.stroke()

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.52, blue: 0.58, alpha: 1),
    .paragraphStyle: titleStyle
]
("After copying, open MyClash from Applications." as NSString).draw(
    in: NSRect(x: 0, y: 36, width: size.width, height: 20),
    withAttributes: footerAttributes
)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render background image\n", stderr)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT

  swift "$generator_script" "$output_path" "$APP_NAME"
}

create_dmg() {
  rm -f "$DMG_PATH" "$RW_DMG_PATH"
  rm -rf "$DMG_WORK_DIR"
  mkdir -p "$MOUNT_DIR"

  local staging_size_kb
  read -r staging_size_kb _ < <(du -sk "$DMG_STAGING_DIR")
  local dmg_size_mb=$((staging_size_kb / 1024 + 64))

  log "creating writable staging image ${RW_DMG_PATH}"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -size "${dmg_size_mb}m" \
    -fs HFS+ \
    -ov \
    "$RW_DMG_PATH" >/dev/null

  log "mounting staging image"
  hdiutil attach "$RW_DMG_PATH" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" >/dev/null

  ditto "$DMG_STAGING_DIR" "$MOUNT_DIR"
  customize_finder_window
  rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes"
  sync

  log "detaching staging image"
  hdiutil detach "$MOUNT_DIR" -quiet

  log "creating ${DMG_PATH}"
  hdiutil convert "$RW_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" >/dev/null
}

customize_finder_window() {
  log "customizing Finder install window"
  osascript <<OSA
set dmgFolder to POSIX file "$MOUNT_DIR" as alias
set backgroundImage to POSIX file "$MOUNT_DIR/${BACKGROUND_DIR_NAME}/${BACKGROUND_FILE_NAME}" as alias

tell application "Finder"
  activate
  open dmgFolder
  delay 1
  set dmgWindow to front window
  tell dmgWindow
    set current view to icon view
    set toolbar visible to false
    set statusbar visible to false
    set bounds to {100, 100, 740, 460}
    set viewOptions to icon view options
    try
      set icon size of viewOptions to 104
    end try
    try
      set text size of viewOptions to 13
    end try
    try
      set background picture of viewOptions to backgroundImage
    end try
  end tell
  try
    set position of item "${APP_NAME}.app" of dmgFolder to {170, 188}
    set position of item "Applications" of dmgFolder to {470, 188}
  end try
  open dmgFolder
  update dmgFolder without registering applications
  delay 1
  close dmgWindow
end tell
OSA
}

verify_dmg() {
  log "verifying ${DMG_PATH}"
  hdiutil verify "$DMG_PATH"
  hdiutil imageinfo "$DMG_PATH" >/dev/null
}

cleanup() {
  if [[ -d "$MOUNT_DIR" ]] && mount | grep -q "on ${MOUNT_DIR} "; then
    hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true
  fi
  rm -rf "$DMG_STAGING_DIR"
  rm -rf "$DMG_WORK_DIR"
  rm -f "$RW_DMG_PATH"
}

main() {
  require_tool hdiutil
  require_tool osascript
  require_tool swift
  require_tool ditto
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
