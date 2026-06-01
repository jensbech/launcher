#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="Sift"
BUNDLE_ID="com.local.sift"
BUILD_DIR=".build/release"
APP_BUNDLE="build/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"

swift build -c release

if [ ! -f Resources/Sift.icns ]; then
    "${SCRIPT_DIR}/make-icon.sh"
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"
cp Resources/Sift.icns "${CONTENTS}/Resources/Sift.icns"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>Sift</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Sift lists and connects your paired Bluetooth devices from the launcher.</string>
    <key>NSBluetoothPeripheralUsageDescription</key><string>Sift lists and connects your paired Bluetooth devices from the launcher.</string>
    <key>NSAudioCaptureUsageDescription</key><string>Sift taps system audio output to drive the "now playing" visualizer in the launcher.</string>
    <key>NSSystemAudioCaptureUsageDescription</key><string>Sift taps system audio output to drive the "now playing" visualizer in the launcher.</string>
</dict>
</plist>
PLIST

ENTITLEMENTS_PLIST="$(mktemp -t sift-entitlements).plist"
cat > "${ENTITLEMENTS_PLIST}" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENT

codesign --force --deep --sign - --entitlements "${ENTITLEMENTS_PLIST}" "${APP_BUNDLE}"
rm -f "${ENTITLEMENTS_PLIST}"

echo "Built ${APP_BUNDLE}"
