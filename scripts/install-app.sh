#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="Sift"
SOURCE_APP="build/${APP_NAME}.app"
INSTALL_DIR="/Applications"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}.app"

"${SCRIPT_DIR}/build-app.sh"

if pgrep -x "${APP_NAME}" >/dev/null; then
    echo "Quitting running ${APP_NAME}..."
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
        pgrep -x "${APP_NAME}" >/dev/null || break
        sleep 0.3
    done
    pkill -x "${APP_NAME}" 2>/dev/null || true
fi

if [ -e "${TARGET_APP}" ]; then
    echo "Removing existing ${TARGET_APP}..."
    rm -rf "${TARGET_APP}"
fi

echo "Installing to ${TARGET_APP}..."
cp -R "${SOURCE_APP}" "${TARGET_APP}"
codesign --force --deep --sign - "${TARGET_APP}"
xattr -dr com.apple.quarantine "${TARGET_APP}" 2>/dev/null || true

echo "Launching ${APP_NAME}..."
open "${TARGET_APP}"

echo "Installed ${TARGET_APP}"
