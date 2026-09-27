#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
INTEGRATION_BUILD_DIR="$(mktemp -d /tmp/file-desensitizer-integration.XXXXXX)"
trap 'rm -rf "$INTEGRATION_BUILD_DIR"' EXIT

if (( $# > 0 )); then
  SOURCE_FILES=("$@")
else
  FIXTURE_DIR="$INTEGRATION_BUILD_DIR/fixtures"
  mkdir -p "$FIXTURE_DIR"
  cp "$SCRIPT_DIR/Tests/generate_excel_fixture.mjs" "$FIXTURE_DIR/"
  ln -s "/Users/jiezhou/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules" "$FIXTURE_DIR/node_modules"
  node "$FIXTURE_DIR/generate_excel_fixture.mjs" "$FIXTURE_DIR"
  SOURCE_FILES=(
    "$FIXTURE_DIR/excel_regression.xlsx"
  )
fi

for source_file in "${SOURCE_FILES[@]}"; do
  if [[ ! -f "$source_file" ]]; then
    print -u2 "测试文件不存在：$source_file"
    exit 1
  fi
done

xcodebuild \
  -project "$SCRIPT_DIR/FileDesensitizer.xcodeproj" \
  -scheme FileDesensitizer \
  -configuration Debug \
  -derivedDataPath "$INTEGRATION_BUILD_DIR" \
  -quiet \
  build

APP_BINARY="$INTEGRATION_BUILD_DIR/Build/Products/Debug/FileDesensitizer.app/Contents/MacOS/FileDesensitizer"
for source_file in "${SOURCE_FILES[@]}"; do
  "$APP_BINARY" --integration-test "$source_file"
done
