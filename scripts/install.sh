#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'macOS only' >&2; exit 1; }
[[ ! -e /var/run/vip.metaver.freemacon ]] || { echo 'End or recover the existing FreeMacOn session before reinstalling.' >&2; exit 1; }
if /usr/bin/pgrep -x FreeMacOn >/dev/null; then echo 'Quit FreeMacOn before installing.' >&2; exit 1; fi
./scripts/build.sh
mkdir -p "$HOME/Applications"
DEST="$HOME/Applications/FreeMacOn.app"
if [[ -e "$DEST" ]]; then echo "Already installed: $DEST. Move the old app to Trash manually after quitting; then run again." >&2; exit 1; fi
/usr/bin/ditto "$PWD/build/FreeMacOn.app" "$DEST"
open "$DEST"
printf 'Installed: %s\n' "$DEST"
