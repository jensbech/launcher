#!/bin/bash
set -euo pipefail

SVG="Resources/AppIcon.svg"
WORK="$(mktemp -d)"
ICONSET="${WORK}/Sift.iconset"
mkdir -p "${ICONSET}"

swift scripts/render-icon.swift "${SVG}" "${ICONSET}"

mkdir -p Resources
iconutil -c icns "${ICONSET}" -o Resources/Sift.icns

rm -rf "${WORK}"
echo "Built Resources/Sift.icns"
