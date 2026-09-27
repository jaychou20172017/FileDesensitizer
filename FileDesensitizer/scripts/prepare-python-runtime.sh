#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
RESOURCE_DIR="$PROJECT_DIR/FileDesensitizer/Resources"
RUNTIME_DIR="$RESOURCE_DIR/PythonRuntime"
PYTHON_VERSION="3.13.15"
OPENPYXL_VERSION="3.1.5"
DEFUSEDXML_VERSION="0.7.1"
ARCHIVE_NAME="cpython-${PYTHON_VERSION}+20260825-aarch64-apple-darwin-install_only_stripped.tar.gz"
ARCHIVE_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20260825/cpython-3.13.15%2B20260825-aarch64-apple-darwin-install_only_stripped.tar.gz"
ARCHIVE_SHA256="149038dd0c194c25d4616d7e42a35f67f2edee96412788f74115819b6a4c8548"

if [[ -x "$RUNTIME_DIR/bin/python3" ]]; then
  installed="$("$RUNTIME_DIR/bin/python3" -c 'import openpyxl, defusedxml; print(openpyxl.__version__)' 2>/dev/null || true)"
  if [[ "$installed" == "$OPENPYXL_VERSION" ]]; then
    print "Python runtime already prepared: $RUNTIME_DIR"
    exit 0
  fi
fi

WORK_DIR="$(mktemp -d /tmp/file-desensitizer-python.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
CACHE_DIR="/private/tmp/filedesensitizer-python-runtime"
ARCHIVE_PATH="$CACHE_DIR/$ARCHIVE_NAME"

print "Downloading Python $PYTHON_VERSION..."
mkdir -p "$CACHE_DIR"
curl --retry 10 --retry-delay 2 --retry-all-errors \
  --continue-at - -LfsS "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
actual_sha="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [[ "$actual_sha" != "$ARCHIVE_SHA256" ]]; then
  print -u2 "Python archive checksum mismatch"
  exit 1
fi

tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR"
"$WORK_DIR/python/bin/python3" -m pip install \
  --disable-pip-version-check \
  --no-cache-dir \
  "openpyxl==$OPENPYXL_VERSION" \
  "defusedxml==$DEFUSEDXML_VERSION"
"$WORK_DIR/python/bin/python3" -c \
  'import openpyxl, defusedxml, zipfile, xml.etree.ElementTree; print(openpyxl.__version__)'

mkdir -p "$RESOURCE_DIR"
if [[ -e "$RUNTIME_DIR" ]]; then
  rm -rf "$RUNTIME_DIR"
fi
mv "$WORK_DIR/python" "$RUNTIME_DIR"

print "Python runtime prepared: $RUNTIME_DIR"
