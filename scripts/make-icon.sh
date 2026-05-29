#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

SVG="Resources/AppIcon.svg"

if [ ! -f "${SVG}" ]; then
    echo "missing ${SVG}" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
ICONSET="${WORK}/Sift.iconset"
mkdir -p "${ICONSET}"

swift "${SCRIPT_DIR}/render-icon.swift" "${SVG}" "${ICONSET}"

mkdir -p Resources
iconutil -c icns "${ICONSET}" -o Resources/Sift.icns

echo "Built Resources/Sift.icns"
