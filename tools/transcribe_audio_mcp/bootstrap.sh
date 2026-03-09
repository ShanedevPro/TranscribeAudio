#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_root=""
if command -v git >/dev/null 2>&1; then
  repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$repo_root" ]]; then
  repo_root="$(cd "$script_dir/../.." && pwd)"
fi

find_python() {
  local candidate
  for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

python_bin="$(find_python || true)"
if [[ -z "$python_bin" ]]; then
  echo "ERROR: Python 3 is required for transcribe_audio_mcp." >&2
  exit 2
fi

tools_root="$repo_root/.tools/transcribe_audio_mcp"
venv_dir="$tools_root/.venv"

mkdir -p "$tools_root"

if [[ ! -d "$venv_dir" ]]; then
  "$python_bin" -m venv "$venv_dir"
fi

python_exec="$venv_dir/bin/python"

echo "Installed transcribe_audio_mcp environment:"
"$python_exec" --version
echo "Server: $script_dir/server.py"
echo "Run: $python_exec $script_dir/server.py"
