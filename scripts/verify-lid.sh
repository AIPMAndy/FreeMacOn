#!/bin/bash
# Read-only workload probe. Does not enable closed-lid mode or change power settings.
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo "macOS only"; exit 2; }
echo "FreeMacOn · supervised lid test (75 seconds)"
echo "Enable a timed closed-lid session first. Keep the Mac on a ventilated desk."
echo "After the 5-second countdown, close the lid for 60 seconds, then reopen."
echo "This probe detects execution gaps, not actual lid state or GUI compatibility."
for n in 5 4 3 2 1; do printf '%s… ' "$n"; sleep 1; done
echo; echo "Close lid now; reopen after about 60 seconds."
start=$(date +%s); last=$start; max_gap=0; samples=0; invalid=0
while :; do
  sleep 2
  now=$(date +%s)
  gap=$((now-last))
  if (( gap < 0 )); then invalid=1; break; fi
  if (( gap > max_gap )); then max_gap=$gap; fi
  samples=$((samples+1)); last=$now
  if (( now-start >= 75 )); then break; fi
done
printf 'Elapsed: %ss | Samples: %s | Largest gap: %ss\n' "$((last-start))" "$samples" "$max_gap"
if (( invalid || max_gap > 8 || samples < 25 )); then
  echo "INCONCLUSIVE / INTERRUPTED: the probe detected a gap or clock change."
  echo "Do not rely on closed-lid mode; end the session and verify sleep recovery."
  exit 1
fi
echo "PASS: no large execution gap observed. Valid only if the lid was physically closed as directed."
echo "End the session and check pmset -g; SleepDisabled should be 0 or absent."
