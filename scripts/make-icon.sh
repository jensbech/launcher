#!/bin/bash
set -euo pipefail

SVG="Resources/AppIcon.svg"
WORK="$(mktemp -d)"
ICONSET="${WORK}/Launcher.iconset"
mkdir -p "${ICONSET}"

swift scripts/render-icon.swift "${SVG}" "${ICONSET}"

mkdir -p Resources
iconutil -c icns "${ICONSET}" -o Resources/Launcher.icns

rm -rf "${WORK}"
echo "Built Resources/Launcher.icns"
