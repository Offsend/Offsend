#!/usr/bin/env bash
# Schema validate + preflight for benchmarks/seal-utility (no LLM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -n "${1:-}" ]]; then
  OFFSEND="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
else
  OFFSEND="$ROOT/target/release/offsend"
fi
BENCH="$ROOT/benchmarks/seal-utility"
VENV="$BENCH/.venv"

if [[ ! -x "$OFFSEND" ]]; then
  echo "offsend binary not found: $OFFSEND" >&2
  exit 2
fi

if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q pyyaml jsonschema pytest

cd "$BENCH"
"$VENV/bin/python" runners/cli.py validate
"$VENV/bin/python" runners/cli.py preflight --offsend "$OFFSEND"
"$VENV/bin/python" -m pytest tests/test_graders.py tests/test_prompt.py tests/test_report.py tests/test_schema.py tests/test_variants.py -q
