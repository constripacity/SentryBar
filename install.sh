#!/bin/bash
# SentryBar installer.
#
# Downloads the latest release and installs it to /Applications, verifying the
# download against the checksum published with the release.
#
#   curl -fsSL https://raw.githubusercontent.com/constripacity/SentryBar/main/install.sh | bash
#
# The previous version of this script curl'd a DMG and copied it into
# /Applications with no verification of any kind, after `rm -rf`-ing whatever
# was already there. For a security tool that is not acceptable: anyone able to
# interfere with the download got code execution, and a failed download
# destroyed the working copy.

set -euo pipefail

APP_NAME="SentryBar"
REPO="constripacity/SentryBar"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
API="https://api.github.com/repos/${REPO}/releases/latest"

WORK_DIR="$(mktemp -d)"
MOUNT_POINT=""

cleanup() {
    [ -n "${MOUNT_POINT}" ] && hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
note() { printf '  %s\n' "$1"; }

# ---------------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || fail "SentryBar is a macOS application."

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if [ "${MACOS_MAJOR}" -lt 13 ]; then
    fail "SentryBar needs macOS 13 or later (this is ${MACOS_VERSION}). It uses MenuBarExtra, which does not exist before Ventura."
fi

command -v curl >/dev/null || fail "curl is required."
command -v shasum >/dev/null || fail "shasum is required."

printf '\nInstalling %s\n\n' "${APP_NAME}"

# ---------------------------------------------------------------------------
note "Finding the latest release…"
RELEASE_JSON="${WORK_DIR}/release.json"
curl -fsSL -H "Accept: application/vnd.github+json" "${API}" -o "${RELEASE_JSON}" \
    || fail "could not reach the GitHub releases API."

VERSION="$(grep -m1 '"tag_name"' "${RELEASE_JSON}" | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
[ -n "${VERSION}" ] || fail "could not determine the latest version."
note "Latest release: ${VERSION}"

DMG_URL="https://github.com/${REPO}/releases/download/${VERSION}/${APP_NAME}.dmg"
SUM_URL="${DMG_URL}.sha256"

# ---------------------------------------------------------------------------
note "Downloading ${APP_NAME}.dmg…"
curl -fL --proto '=https' --tlsv1.2 "${DMG_URL}" -o "${WORK_DIR}/${APP_NAME}.dmg" \
    || fail "download failed."

note "Downloading the published checksum…"
if ! curl -fsSL --proto '=https' --tlsv1.2 "${SUM_URL}" -o "${WORK_DIR}/expected.sha256"; then
    fail "no checksum was published for ${VERSION} at ${SUM_URL}.
  Refusing to install an unverifiable download. Please open an issue — a
  release without a checksum is a bug in the release workflow, not in your setup."
fi

EXPECTED="$(awk '{print $1}' "${WORK_DIR}/expected.sha256" | head -1)"
ACTUAL="$(shasum -a 256 "${WORK_DIR}/${APP_NAME}.dmg" | awk '{print $1}')"
if [ "${EXPECTED}" != "${ACTUAL}" ]; then
    fail "checksum mismatch — the download does not match what was published.
  expected ${EXPECTED}
  got      ${ACTUAL}
  Nothing has been installed. Do not retry blindly; report this."
fi
note "Checksum verified: ${ACTUAL}"

# ---------------------------------------------------------------------------
note "Mounting the disk image…"
MOUNT_POINT="${WORK_DIR}/mnt"
mkdir -p "${MOUNT_POINT}"
hdiutil attach "${WORK_DIR}/${APP_NAME}.dmg" -nobrowse -quiet -mountpoint "${MOUNT_POINT}" \
    || fail "could not mount the disk image."

[ -d "${MOUNT_POINT}/${APP_NAME}.app" ] || fail "the disk image does not contain ${APP_NAME}.app."

# Staged install: the new copy is put in place before the old one is removed, so
# an interrupted install never leaves you with no application at all.
STAGED="${WORK_DIR}/${APP_NAME}.app"
note "Copying…"
cp -R "${MOUNT_POINT}/${APP_NAME}.app" "${STAGED}"

if [ -d "${INSTALL_DIR}/${APP_NAME}.app" ]; then
    note "Replacing the existing installation…"
    BACKUP="${WORK_DIR}/${APP_NAME}.app.previous"
    mv "${INSTALL_DIR}/${APP_NAME}.app" "${BACKUP}"
    if ! mv "${STAGED}" "${INSTALL_DIR}/${APP_NAME}.app"; then
        mv "${BACKUP}" "${INSTALL_DIR}/${APP_NAME}.app"
        fail "install failed; your previous version has been put back."
    fi
else
    mv "${STAGED}" "${INSTALL_DIR}/${APP_NAME}.app" || fail "could not write to ${INSTALL_DIR}."
fi

# ---------------------------------------------------------------------------
printf '\n\033[32m%s %s installed to %s\033[0m\n\n' "${APP_NAME}" "${VERSION}" "${INSTALL_DIR}"

if ! codesign --verify --deep --strict "${INSTALL_DIR}/${APP_NAME}.app" >/dev/null 2>&1; then
    cat <<'WARNING'
  This build is NOT code-signed or notarised.

  macOS Gatekeeper will refuse to open it until you clear the quarantine flag:

      xattr -dr com.apple.quarantine /Applications/SentryBar.app

  You are being told this rather than having the script do it for you: a script
  that silently disarms Gatekeeper on your behalf is exactly the pattern you
  should refuse from anyone, including this one.

WARNING
fi

printf '  Open it with:  open -a %s\n\n' "${APP_NAME}"
