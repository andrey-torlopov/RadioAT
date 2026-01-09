#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/markondej/fm_transmitter"
TARGET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Sources/FMTransmitterCLib/vendor/fm_transmitter"

if [ -d "$TARGET_DIR/.git" ]; then
  echo "fm_transmitter sources already present in $TARGET_DIR"
  exit 0
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "Fetching fm_transmitter sources into $TARGET_DIR"
if command -v git >/dev/null 2>&1; then
  git clone --depth 1 "$REPO_URL" "$TARGET_DIR"
else
  echo "git is required to fetch sources from $REPO_URL" >&2
  exit 1
fi

echo "Done. Verify files: fm_transmitter.cpp, transmitter.cpp, mailbox.cpp, wave_reader.cpp."
