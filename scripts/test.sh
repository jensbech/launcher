#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

swift test \
  -Xswiftc -F -Xswiftc "${FRAMEWORKS}" \
  -Xlinker -F -Xlinker "${FRAMEWORKS}" \
  -Xlinker -rpath -Xlinker "${FRAMEWORKS}" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  "$@"
