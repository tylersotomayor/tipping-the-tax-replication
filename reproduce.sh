#!/bin/bash
# One-button replication: rebuilds any missing input cells from the public
# TLC records, runs the full Stata pipeline (every table and figure), and
# compiles the paper.
#
#   ./reproduce.sh              # rebuild missing cells, run pipeline, build paper
#   ./reproduce.sh --cells-only # just rebuild the unversioned input cells
#   ./reproduce.sh --no-paper   # skip the LaTeX build
#
# Requirements: see README.md (Stata 18+, Python 3.10+ with duckdb, TeX Live).
set -euo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-python3}"

echo "== Step 1/3: input cells =="
declare -a PAIRS=(
  "cells_minute.csv:build_cells.py"
  "cells_minute_v3.csv:build_cells_v3.py"
  "cells_minute_vendor.csv:build_cells_vendor.py"
  "cells_minute_6am.csv:build_cells_6am.py"
  "cells_minute_jfk.csv:build_cells_jfk.py"
  "cells_minute_decomp.csv:build_cells_decomp.py"
)
for pair in "${PAIRS[@]}"; do
  f="${pair%%:*}"; b="${pair##*:}"
  if [ -f "data/cells/$f" ]; then
    echo "  data/cells/$f present -- skipping"
  else
    echo "  building data/cells/$f  (downloads monthly TLC parquet; deterministic)"
    "$PY" "code/py/$b"
  fi
done
[ "${1:-}" = "--cells-only" ] && { echo "Cells complete."; exit 0; }

echo "== Step 2/3: Stata pipeline (code/00_master.do) =="
./run_stata.sh

if [ "${1:-}" != "--no-paper" ]; then
  echo "== Step 3/3: paper (compile.sh) =="
  ./compile.sh
fi
echo "Replication complete. Exhibits in output/, log in logs/stata-master.log, paper at main.pdf."
