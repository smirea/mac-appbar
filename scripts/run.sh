#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
app_name="MacAppBar"
bundle_path="$repo_root/.build/release/$app_name.app"
executable_path="$bundle_path/Contents/MacOS/$app_name"

cd "$repo_root"

if [[ ! -x "$executable_path" ]]; then
    "$script_dir/build-app.sh"
fi

"$executable_path" >/dev/null 2>&1 &
