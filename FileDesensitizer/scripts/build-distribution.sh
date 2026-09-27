#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
WORKSPACE_DIR="${PROJECT_DIR:h}"
DIST_DIR="$WORKSPACE_DIR/dist"
BUILD_DIR="$(mktemp -d /tmp/file-desensitizer-distribution.XXXXXX)"
STAGING_DIR="$BUILD_DIR/dmg"
APP_PATH="$BUILD_DIR/Build/Products/Release/FileDesensitizer.app"
DMG_PATH="$DIST_DIR/FileDesensitizer-1.0-macOS-arm64.dmg"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR" "$STAGING_DIR"

xcodebuild \
  -project "$PROJECT_DIR/FileDesensitizer.xcodeproj" \
  -scheme FileDesensitizer \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination "platform=macOS,arch=arm64" \
  ONLY_ACTIVE_ARCH=YES \
  build

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  /usr/bin/codesign --force --deep --options runtime --sign - "$APP_PATH"
fi

/usr/bin/codesign --verify --deep --strict "$APP_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/FileDesensitizer.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/ditto "$WORKSPACE_DIR/distribution/安装说明.txt" "$STAGING_DIR/安装说明.txt"

/usr/bin/hdiutil create \
  -volname "文件脱敏工具" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --strict "$DMG_PATH"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    /usr/bin/xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" --wait
    /usr/bin/xcrun stapler staple "$DMG_PATH"
    /usr/bin/xcrun stapler validate "$DMG_PATH"
  fi
fi

/usr/bin/shasum -a 256 "$DMG_PATH"
print "分发包已生成：$DMG_PATH"
