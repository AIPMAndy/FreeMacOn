#!/bin/bash
# Explicitly ordinary idle keep-awake only. No global power setting changes.
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo "macOS only" >&2; exit 2; }
[[ $# -gt 0 ]] || { echo "Usage: $0 command [args...]" >&2; exit 2; }
echo "FreeMacOn: idle keep-awake for this command; does NOT guarantee closed-lid execution." >&2
exec /usr/bin/caffeinate -i "$@"
