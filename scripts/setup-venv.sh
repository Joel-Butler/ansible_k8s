#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v uv >/dev/null 2>&1; then
    echo "uv is not installed. Install it with: brew install uv" >&2
    echo "  (or see https://docs.astral.sh/uv/getting-started/installation/)" >&2
    exit 1
fi

uv sync

echo
echo "Done. Activate with: source .venv/bin/activate"
echo "Or run ad-hoc commands without activating: uv run ansible-playbook ..."
