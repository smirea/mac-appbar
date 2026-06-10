#!/usr/bin/env bash
set -euo pipefail

state_path="${1:-$HOME/.cache/mac-appbar/bartender-state.json}"

/usr/bin/python3 - "$state_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    payload = json.loads(path.read_text())
except Exception:
    print("false")
else:
    print("true" if payload.get("needs_attention") else "false")
PY
