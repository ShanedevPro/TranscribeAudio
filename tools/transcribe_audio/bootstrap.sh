#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_root=""
if command -v git >/dev/null 2>&1; then
  repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "${repo_root}" ]]; then
  repo_root="$(cd "$script_dir/../.." && pwd)"
fi

find_python() {
  local candidate
  for candidate in python3.12 python3.11 python3.10; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

python_bin="$(find_python || true)"
if [[ -z "$python_bin" ]]; then
  cat <<'EOF' >&2
ERROR: Python 3.10+ is required for this tool.
Please install Python 3.10 or newer, then re-run bootstrap.sh.
EOF
  exit 2
fi

tools_root="$repo_root/.tools/transcribe_audio"
venv_dir="$tools_root/.venv"
pip_cache_dir="$tools_root/pip-cache"

mkdir -p "$tools_root" "$pip_cache_dir"

if [[ ! -d "$venv_dir" ]]; then
  "$python_bin" -m venv "$venv_dir"
fi

pip="$venv_dir/bin/pip"
python_exec="$venv_dir/bin/python"

export PIP_CACHE_DIR="$pip_cache_dir"

"$pip" install -U pip
"$pip" install -r "$script_dir/requirements.txt"

echo "Installed transcribe tool environment:"
"$python_exec" --version
echo "Venv: $venv_dir"
echo "Run CLI: $python_exec $script_dir/transcribe_cli.py export_state"
echo "Run native app: $repo_root/apps/TranscribeAudioMac/run.sh"
