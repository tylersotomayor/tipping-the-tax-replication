#!/bin/bash
# check_refs.sh -- audit \label{} definitions and \ref-family references
# in the modular paper source, and report broken or orphaned links.
#
# Usage: ./check_refs.sh              # summary report
#        ./check_refs.sh --strict     # also flag naming-convention violations
#
# Convention: labels must start with one of the following prefixes,
# matching the entity they label:
#   sec:    \section / \subsection / \subsubsection
#   app:    appendix sections
#   fig:    figures
#   tab:    tables
#   eq:     numbered equations
#   prop:   propositions / lemmas / corollaries
#   par:    paragraph-level runins (optional)
set +e

cd "$(dirname "$0")"

STRICT=0
if [ "$1" = "--strict" ]; then STRICT=1; fi

SOURCES=$(find . -name "*.tex" -not -path "./build/*" | sort)

# Extract all \label{...} identifiers
LABELS=$(grep -h -oE '\\label\{[^}]+\}' $SOURCES | \
         sed -E 's/\\label\{([^}]+)\}/\1/g' | sort -u)

# Extract all ref-family identifiers: \ref{}, \autoref{}, \cref{}, \Cref{},
# \pageref{}, \eqref{}, \vref{}
REFS=$(grep -h -oE '\\(ref|autoref|cref|Cref|pageref|eqref|vref)\{[^}]+\}' $SOURCES | \
       sed -E 's/\\(ref|autoref|cref|Cref|pageref|eqref|vref)\{([^}]+)\}/\2/g' | sort -u)

echo "========================================"
echo "  LaTeX label / reference audit"
echo "========================================"
echo ""
echo "Labels defined:       $(echo "$LABELS" | grep -c . || echo 0)"
echo "References to labels: $(echo "$REFS" | grep -c . || echo 0)"
echo ""

# Broken references: refs that point to labels not defined
echo "--- Broken references (\\ref to a non-existent \\label) ---"
BROKEN=$(comm -23 <(echo "$REFS") <(echo "$LABELS"))
if [ -z "$BROKEN" ]; then
  echo "  (none)"
else
  echo "$BROKEN" | sed 's/^/  /'
fi
echo ""

# Orphan labels: defined but never referenced
echo "--- Orphan labels (\\label never referenced) ---"
ORPHAN=$(comm -13 <(echo "$REFS") <(echo "$LABELS"))
if [ -z "$ORPHAN" ]; then
  echo "  (none)"
else
  echo "$ORPHAN" | sed 's/^/  /'
fi
echo ""

if [ "$STRICT" = "1" ]; then
  echo "--- Naming-convention violations (prefix not sec:/app:/fig:/tab:/eq:/prop:/par:) ---"
  BAD=$(echo "$LABELS" | grep -Ev '^(sec|fig|tab|eq|app|par|prop|lem|cor|def|asm):')
  if [ -z "$BAD" ]; then
    echo "  (none)"
  else
    echo "$BAD" | sed 's/^/  /'
  fi
  echo ""
fi

# Reference-per-file listing
echo "--- Labels by file ---"
for f in $SOURCES; do
  L=$(grep -oE '\\label\{[^}]+\}' "$f" | sed -E 's/\\label\{([^}]+)\}/\1/g')
  if [ -n "$L" ]; then
    N=$(echo "$L" | wc -l | tr -d ' ')
    echo "  $f  ($N label$( [ $N -gt 1 ] && echo s ))"
    echo "$L" | sed 's/^/      /'
  fi
done
