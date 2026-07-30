#!/bin/bash
# Compile main.tex with 3-pass pdflatex + biber
# Build artifacts go to build/ to keep the paper root clean
# Usage: ./compile.sh [--clean]
set -e

cd "$(dirname "$0")"

if [ "$1" = "--clean" ]; then
  rm -rf build/*.aux build/*.bbl build/*.bcf build/*.blg build/*.log build/*.out build/*.toc build/*.run.xml build/*.pdf
  echo "Build artifacts cleaned."
  exit 0
fi

mkdir -p build

# First pass
pdflatex -output-directory=build -interaction=nonstopmode main.tex

# Bibliography
biber --output-directory=build --input-directory=build main

# Second + third pass
pdflatex -output-directory=build -interaction=nonstopmode main.tex
pdflatex -output-directory=build -interaction=nonstopmode main.tex

# Copy final PDF to paper root for easy access
cp build/main.pdf main.pdf

echo ""
echo "Done: main.pdf"
