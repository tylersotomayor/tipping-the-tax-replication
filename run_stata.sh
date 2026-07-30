#!/bin/bash
# Run the complete analysis pipeline with StataBE.
set -euo pipefail

cd "$(dirname "$0")"

# Locate a Stata binary. Prefer StataBE (the documented house standard); fall
# back to whatever edition is installed on this machine.
STATA_BE="${STATA:-}"
if [ -n "$STATA_BE" ] && [ ! -x "$STATA_BE" ]; then
  echo "STATA env var set but not executable: $STATA_BE" >&2; exit 1
fi
[ -z "$STATA_BE" ] && for cand in \
  /Applications/StataNow/StataBE.app/Contents/MacOS/StataBE \
  /Applications/Stata/StataBE.app/Contents/MacOS/StataBE \
  /Applications/StataNow/StataSE.app/Contents/MacOS/StataSE \
  /Applications/Stata/StataSE.app/Contents/MacOS/StataSE \
  /Applications/StataNow/StataMP.app/Contents/MacOS/StataMP \
  /Applications/Stata/StataMP.app/Contents/MacOS/StataMP ; do
  if [ -x "$cand" ]; then STATA_BE="$cand"; break; fi
done

if [ -z "$STATA_BE" ]; then
  echo "No Stata binary found under /Applications/Stata* -- checked BE, SE, MP." >&2
  exit 1
fi
echo "Using: $STATA_BE"

mkdir -p logs data/intermediate data/processed output/figures output/tables

"$STATA_BE" -e do code/00_master.do

if [ -f 00_master.log ]; then
  mv 00_master.log logs/stata-console.log
fi

echo "Done: StataBE pipeline completed."
