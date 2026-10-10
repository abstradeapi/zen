#!/bin/bash
set -euo pipefail
# ─────────────────────────────────────────────
# install-chrome.sh — Install Google Chrome
# Supports: Debian/Ubuntu, Fedora, RHEL/CentOS, Arch Linux
# ─────────────────────────────────────────────

export DEBIAN_FRONTEND=noninteractive

# ── Helpers ──────────────────────────────────
log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

# Allow script to run as root OR via sudo
maybe_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ── Architecture guard ────────────────────────
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    err "Google Chrome only supports x86_64. Detected: $ARCH"
fi

log "Starting Chrome installation on $(lsb_release -ds 2>/dev/null || uname -sr)..."

# ── Package manager detection ─────────────────
if command -v apt-get >/dev/null 2>&1; then
    # ── Debian / Ubuntu ──────────────────────
    log "Detected apt-based system."
    maybe_sudo apt-get update -y
    maybe_sudo apt-get upgrade -y
    maybe_sudo apt-get install -y wget curl

    CHROME_DEB=$(mktemp /tmp/chrome-XXXXXX.deb)
    log "Downloading Chrome..."
    wget -q -O "$CHROME_DEB" \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

    log "Installing Chrome..."
    # Use apt (not dpkg) so dependencies are resolved automatically
    maybe_sudo apt-get install -y "$CHROME_DEB" || {
        # Fallback: fix broken deps then retry
        maybe_sudo apt-get install -f -y
        maybe_sudo apt-get install -y "$CHROME_DEB"
    }
    rm -f "$CHROME_DEB"

elif command -v dnf >/dev/null 2>&1; then
    # ── Fedora / RHEL 8+ ─────────────────────
    log "Detected dnf-based system."
    maybe_sudo dnf upgrade -y --refresh
    log "Installing Chrome..."
    maybe_sudo dnf install -y \
        https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm

elif command -v yum >/dev/null 2>&1; then
    # ── CentOS / RHEL 7 ──────────────────────
    log "Detected yum-based system."
    maybe_sudo yum update -y
    log "Installing Chrome..."
    maybe_sudo yum install -y \
        https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm

elif command -v pacman >/dev/null 2>&1; then
    # ── Arch Linux ───────────────────────────
    # makepkg MUST NOT run as root; use a build user if needed
    log "Detected Arch-based system."
    maybe_sudo pacman -Syu --noconfirm
    maybe_sudo pacman -S --noconfirm --needed base-devel git

    BUILD_DIR=$(mktemp -d /tmp/google-chrome-XXXXXX)
    git clone https://aur.archlinux.org/google-chrome.git "$BUILD_DIR"

    if [ "$(id -u)" -eq 0 ]; then
        # Running as root: create a temporary unprivileged build user
        log "Running as root — creating temp build user for makepkg..."
        useradd -m -d /tmp/chromebuild _chromebuild 2>/dev/null || true
        cp -r "$BUILD_DIR/." /tmp/chromebuild/
        chown -R _chromebuild:_chromebuild /tmp/chromebuild/
        # Allow the build user to install packages via pacman without password
        echo "_chromebuild ALL=(ALL) NOPASSWD: /usr/bin/pacman" \
            > /etc/sudoers.d/chromebuild
        su -s /bin/bash _chromebuild -c \
            "cd /tmp/chromebuild && makepkg -si --noconfirm"
        # Cleanup
        userdel -r _chromebuild 2>/dev/null || true
        rm -f /etc/sudoers.d/chromebuild
    else
        (cd "$BUILD_DIR" && makepkg -si --noconfirm)
    fi
    rm -rf "$BUILD_DIR"

else
    err "No supported package manager found (apt/dnf/yum/pacman)."
fi

# ── Verify installation ───────────────────────
if command -v google-chrome >/dev/null 2>&1; then
    log "Chrome installed successfully:"
    google-chrome --version
else
    err "Installation completed but 'google-chrome' not found in PATH."
fi
