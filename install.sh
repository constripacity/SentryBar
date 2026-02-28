#!/bin/bash
# SentryBar Installer
# Downloads the latest release and installs to /Applications
set -euo pipefail

APP_NAME="SentryBar"
REPO="constripacity/SentryBar"
DMG_URL="https://github.com/${REPO}/releases/latest/download/${APP_NAME}.dmg"
TMP_DMG="/tmp/${APP_NAME}.dmg"
MOUNT_POINT="/Volumes/${APP_NAME}"
INSTALL_DIR="/Applications"

echo "Installing ${APP_NAME}..."

# Download latest DMG
echo "Downloading latest release..."
curl -fsSL "${DMG_URL}" -o "${TMP_DMG}"

# Mount DMG
echo "Mounting disk image..."
hdiutil attach "${TMP_DMG}" -nobrowse -quiet

# Copy app (remove old version if present)
if [ -d "${INSTALL_DIR}/${APP_NAME}.app" ]; then
    echo "Removing previous version..."
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
fi

echo "Installing to ${INSTALL_DIR}..."
cp -R "${MOUNT_POINT}/${APP_NAME}.app" "${INSTALL_DIR}/"

# Clean up
echo "Cleaning up..."
hdiutil detach "${MOUNT_POINT}" -quiet
rm -f "${TMP_DMG}"

echo "${APP_NAME} installed successfully!"
echo "Open it from your Applications folder or run:"
echo "  open -a ${APP_NAME}"
