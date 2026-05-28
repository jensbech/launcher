#!/bin/bash
set -euo pipefail

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

swift test \
  -Xswiftc -F -Xswiftc "${FRAMEWORKS}" \
  -Xlinker -F -Xlinker "${FRAMEWORKS}" \
  -Xlinker -rpath -Xlinker "${FRAMEWORKS}" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  "$@"
