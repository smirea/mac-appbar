#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
app_name="MacAppBar"
bundle_path="$repo_root/.build/release/$app_name.app"
executable_path="$bundle_path/Contents/MacOS/$app_name"

cd "$repo_root"

process_pattern="[M]acAppBar.app/Contents/MacOS/$app_name"
pkill -f "$process_pattern" 2>/dev/null || true
for _ in {1..20}; do
    if ! pgrep -f "$process_pattern" >/dev/null; then
        break
    fi
    sleep 0.1
done

if [[ ! -x "$executable_path" ]]; then
    "$script_dir/build-app.sh"
fi

open -n "$bundle_path"
