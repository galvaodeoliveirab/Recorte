#!/bin/bash
# Testa o algoritmo da captura com rolagem. Uso: scripts/test-stitcher.sh imagem.png
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
swiftc -O -o "$OUT/st" Tests/stitch-test.swift Sources/Recorte/Stitcher.swift
"$OUT/st" "$1"
