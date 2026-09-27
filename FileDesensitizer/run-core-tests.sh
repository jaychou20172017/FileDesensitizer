#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
TEST_BUILD_DIR="$(mktemp -d /tmp/file-desensitizer-tests.XXXXXX)"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT

xcrun swiftc \
  "$SCRIPT_DIR/FileDesensitizer/Models/FieldInfo.swift" \
  "$SCRIPT_DIR/FileDesensitizer/Utilities/RegexPatterns.swift" \
  "$SCRIPT_DIR/FileDesensitizer/Utilities/FileFormatUtils.swift" \
  "$SCRIPT_DIR/Tests/main.swift" \
  -o "$TEST_BUILD_DIR/CoreLogicTests"

"$TEST_BUILD_DIR/CoreLogicTests"
