#!/bin/bash

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="${SCRIPT_DIR}/zen.sh"
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
REMOTE="pcloud"
APP="$1"
ACTION="$2"

# Function to check and install rclone
check_rclone() {
    if ! command -v rclone &> /dev/null; then
        echo "Installing rclone..."
        curl -fsS https://rclone.org/install.sh | sudo bash
    fi
}

# Function to setup pCloud remote with persistent token
setup_pcloud() {
    if [ -f "$RCLONE_CONF" ] && rclone listremotes | grep -q "^$REMOTE:"; then
        echo "pCloud remote already configured. Reusing existing credentials."
        return
    fi
    echo "Setting up pCloud remote (one-time setup). You need a pCloud account (10GB free storage)."
    echo "Visit https://my.pcloud.com/#page=apikeys to generate an API token."
    read -p "Enter your pCloud API token: " api_token
    read -p "Enter your pCloud hostname (e.g., api.pcloud.com for US, eapi.pcloud.com for EU): " hostname
    mkdir -p "$(dirname "$RCLONE_CONF")"
    cat > "$RCLONE_CONF" <<EOL
[$REMOTE]
type = pcloud
token = $api_token
hostname = $hostname
EOL
    if ! rclone lsd "$REMOTE:" &> /dev/null; then
        echo "Error: pCloud configuration failed. Check API token and hostname."
        rm -f "$RCLONE_CONF"
        exit 1
    fi
    echo "pCloud setup complete. Credentials saved in $RCLONE_CONF for reuse."
}

# Function to setup Chrome, npm, Python
setup_env() {
    echo "Setting up Chrome, npm, Python..."
    sudo apt update
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
    sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
    sudo apt install -y google-chrome-stable
    sudo apt install -y nodejs npm
    sudo apt install -y python3 python3-pip
    echo "Setup complete."
}

# Backup paths
BACKUP_DIR="$HOME/zen_backup_$(date +%Y%m%d_%H%M%S)"
CHROME_DIR="$HOME/.config/google-chrome"
NPM_GLOBAL="$HOME/.npm-global"
PIP_CACHE="$HOME/.cache/pip"
PYTHON_SITE="$HOME/.local/lib/python3.*"

# Function: Auto-delete app
autodel() {
    local app="$1"
    if [[ -z "$app" ]]; then
        echo "Usage: zen autodel <app_name>"
        exit 1
    fi
    echo "🔍 Searching for files containing '$app'..."
    results=$(sudo find / -iname "*${app}*" 2>/dev/null || true)
    if [[ -z "$results" ]]; then
        echo "No files found for '$app'."
        exit 0
    fi
    echo "Found files:"
    echo "$results"
    echo
    read -rp "❓ Delete everything under /config/ for '$app'? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "🗑 Deleting..."
        echo "$results" | grep "^/config/" | xargs -r sudo rm -rf
        echo "✅ Deleted."
        deb_file=$(find /config/ -maxdepth 1 -iname "*.deb" -print -quit)
        if [[ -n "$deb_file" ]]; then
            pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null || true)
            if [[ -n "$pkg_name" ]]; then
                echo "📦 Removing package '$pkg_name'..."
                sudo apt remove --purge -y "$pkg_name" && sudo apt autoremove -y || echo "⚠️ Package not installed."
            fi
        fi
    else
        echo "❌ Cancelled."
    fi
}

# Function: Docker install/uninstall
docker_manage() {
    case "$1" in
        install)
            echo "🐳 Installing Docker..."
            sudo apt update && sudo apt install -y ca-certificates curl gnupg lsb-release
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            echo "✅ Docker installed."
            ;;
        uninstall)
            echo "🧹 Uninstalling Docker..."
            sudo apt remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo apt autoremove -y
            sudo rm -rf /var/lib/docker /var/lib/containerd
            echo "✅ Docker removed."
            ;;
        *)
            echo "Usage: zen docker [install|uninstall]"
            ;;
    esac
}

# Function: System Update
sys_update() {
    echo "⬆️ Updating system..."
    sudo apt update && sudo apt upgrade -y
    echo "🔧 Installing helper tools..."
    sudo apt install -y gnome-keyring wget curl git unzip htop
    echo "✅ System updated."
}

# Function: Webtop
webtop_manage() {
    case "$1" in
        stop)
            echo "🛑 Stopping webtop..."
            docker stop webtopo || true
            docker rm webtopo || true
            echo "✅ Webtop stopped."
            ;;
        *)
            echo "🚀 Starting Webtop container..."
            docker run -d \
              --name=webtopo \
              --security-opt seccomp=unconfined \
              -e PUID=1000 \
              -e PGID=1000 \
              -e TZ=Etc/UTC \
              -e SUBFOLDER=/ \
              -e TITLE=Webtop \
              -p 3000:3000 \
              -p 3001:3001 \
              --shm-size="8gb" \
              --restart unless-stopped \
              ghcr.io/tibor309/webtop:ubuntu
            echo "✅ Webtop started on http://localhost:3000"
            ;;
    esac
}

# Main Dispatcher
case "$APP" in
    "upload")
        check_rclone
        setup_pcloud
        echo "Starting upload backup..."
        mkdir -p "$BACKUP_DIR"
        if [ -d "$CHROME_DIR" ]; then
            tar -czf "$BACKUP_DIR/chrome_data.tar.gz" "$CHROME_DIR"
        fi
        if [ -d "$NPM_GLOBAL" ]; then
            tar -czf "$BACKUP_DIR/npm_packages.tar.gz" "$NPM_GLOBAL"
        else
            npm list -g --depth=0 --parseable | while read -r pkg; do
                [ -n "$pkg" ] && tar -czf "$BACKUP_DIR/npm_$(basename "$pkg").tar.gz" "$HOME/.npm"
            done
        fi
        if [ -d "$PIP_CACHE" ]; then
            tar -czf "$BACKUP_DIR/pip_cache.tar.gz" "$PIP_CACHE"
        fi
        if [ -d "$PYTHON_SITE" ]; then
            tar -czf "$BACKUP_DIR/python_site.tar.gz" "$PYTHON_SITE"
        fi
        rclone sync "$BACKUP_DIR" "$REMOTE:/zen_backup" --progress --transfers 4
        echo "Upload complete. Local backup in $BACKUP_DIR."
        ;;
    "download")
        check_rclone
        if ! [ -f "$RCLONE_CONF" ] || ! rclone listremotes | grep -q "^$REMOTE:"; then
            echo "pCloud not configured. Run 'zen upload' first to setup."
            exit 1
        fi
        echo "Starting download and restore..."
        TEMP_DIR="$HOME/zen_temp_download"
        mkdir -p "$TEMP_DIR"
        rclone sync "$REMOTE:/zen_backup" "$TEMP_DIR" --progress --transfers 4
        if [ -f "$TEMP_DIR/chrome_data.tar.gz" ]; then
            tar -xzf "$TEMP_DIR/chrome_data.tar.gz" -C "$HOME/.config/"
        fi
        if [ -f "$TEMP_DIR/npm_packages.tar.gz" ]; then
            tar -xzf "$TEMP_DIR/npm_packages.tar.gz" -C "$HOME/"
        fi
        if [ -f "$TEMP_DIR/pip_cache.tar.gz" ]; then
            tar -xzf "$TEMP_DIR/pip_cache.tar.gz" -C "$HOME/"
        fi
        if [ -f "$TEMP_DIR/python_site.tar.gz" ]; then
            tar -xzf "$TEMP_DIR/python_site.tar.gz" -C "$HOME/.local/"
        fi
        rm -rf "$TEMP_DIR"
        echo "Download and restore complete."
        ;;
    "setup")
        setup_env
        ;;
    "install")
        echo "Installing $SCRIPT_NAME..."
        sudo curl -fsS -o "$SCRIPT_NAME" "$0"
        sudo chmod +x "$SCRIPT_NAME"
        echo "Script installed to $SCRIPT_NAME. Run with zen {upload|download|setup|install-self|uninstall-self|hello|autodel|docker|update|webtop}"
        ;;
    "install-self")
        SCRIPT_PATH="$(realpath "$0")"
        echo "📦 Installing zen to /usr/local/bin..."
        sudo cp "$SCRIPT_PATH" /usr/local/bin/zen
        sudo chmod +x /usr/local/bin/zen
        echo "✅ Installed! You can now run: zen hello"
        ;;
    "uninstall-self")
        echo "🧹 Removing zen from /usr/local/bin..."
        sudo rm -f /usr/local/bin/zen
        echo "✅ Removed zen."
        ;;
    "hello")
        echo "👋 Hello from zen! ✅"
        ;;
    "autodel")
        autodel "$ACTION"
        ;;
    "docker")
        docker_manage "$ACTION"
        ;;
    "update")
        sys_update
        ;;
    "webtop")
        webtop_manage "$ACTION"
        ;;
    *)
        echo "🔧 zen - Available commands:"
        echo "  zen upload                   # Backup data and upload to pCloud"
        echo "  zen download                 # Download and restore data from pCloud"
        echo "  zen setup                    # Install Chrome, npm, Python"
        echo "  zen install                  # Auto-install this script"
        echo "  zen install-self             # Install zen globally"
        echo "  zen uninstall-self           # Remove zen"
        echo "  zen hello                    # Test command"
        echo "  zen autodel <app>            # Search and delete app files"
        echo "  zen docker install|uninstall # Install or uninstall Docker"
        echo "  zen update                   # System update + helper tools"
        echo "  zen webtop                   # Start Webtop container"
        echo "  zen webtop stop              # Stop Webtop container"
        ;;
esac
