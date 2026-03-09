#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p .build-cache/clang .build-cache/swiftpm
export CLANG_MODULE_CACHE_PATH="$SCRIPT_DIR/.build-cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRIPT_DIR/.build-cache/swiftpm"

swift run
