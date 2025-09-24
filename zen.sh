#!/usr/bin/env bash
# zen - Ubuntu helper script (auto-delete apps, docker setup, system update, self-installer)

set -e

APP="$1"
ACTION="$2"
TARGET="$3"

### --- Self-Installer ---
if [[ "$APP" == "install-self" ]]; then
    echo "📦 Installing zen to /usr/local/bin..."
    chmod +x "$0"
    sudo cp "$0" /usr/local/bin/zen
    echo "✅ Installed! Now you can run 'zen' from anywhere."
    exit 0
fi

### --- Function: Auto-delete app ---
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
    read -rp "❓ Do you want to delete everything under /config/ containing '$app'? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "🗑 Deleting related files from /config/..."
        echo "$results" | grep "^/config/" | xargs -r sudo rm -rf
        echo "✅ Files deleted."

        # Try to uninstall package if there is a .deb file in /config/
        deb_file=$(find /config/ -maxdepth 1 -iname "*.deb" -print -quit)
        if [[ -n "$deb_file" ]]; then
            pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null || true)
            if [[ -n "$pkg_name" ]]; then
                echo "📦 Attempting to remove package '$pkg_name'..."
                sudo apt remove --purge -y "$pkg_name" && sudo apt autoremove -y || echo "⚠️ Package not installed or removal failed."
            fi
        fi
    else
        echo "❌ Deletion cancelled."
        exit 0
    fi
}

### --- Function: Docker install/uninstall ---
docker_manage() {
    case "$1" in
        install)
            echo "🐳 Installing Docker..."
            sudo apt update && sudo apt install -y ca-certificates curl gnupg lsb-release
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            echo "✅ Docker installed successfully."
            ;;
        uninstall)
            echo "🧹 Uninstalling Docker..."
            sudo apt remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo apt autoremove -y
            sudo rm -rf /var/lib/docker /var/lib/containerd
            echo "✅ Docker fully removed."
            ;;
        *)
            echo "Usage: zen docker [install|uninstall]"
            exit 1
            ;;
    esac
}

### --- Function: System Update ---
sys_update() {
    echo "⬆️ Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    echo "🔧 Installing helper tools..."
    sudo apt install -y gnome-keyring wget curl git unzip htop
    echo "✅ System updated and helper tools installed."
}

### --- Main Entry ---
case "$APP" in
    autodel)
        autodel "$ACTION"
        ;;
    docker)
        docker_manage "$ACTION"
        ;;
    update)
        sys_update
        ;;
    *)
        echo "Usage:"
        echo "  zen install-self             # Install zen to /usr/local/bin"
        echo "  zen autodel <app_name>       # Search, confirm, delete & uninstall app"
        echo "  zen docker install|uninstall # Install or uninstall Docker"
        echo "  zen update                   # System update + helper tools"
        ;;
esac
