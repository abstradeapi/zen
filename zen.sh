#!/usr/bin/env bash
# zen - Ubuntu helper script

set -e

APP="$1"
ACTION="$2"

### --- Self-Installer ---
if [[ "$APP" == "install-self" ]]; then
    SCRIPT_PATH="$(realpath "$0")"
    echo "📦 Installing zen to /usr/local/bin..."
    sudo cp "$SCRIPT_PATH" /usr/local/bin/zen
    sudo chmod +x /usr/local/bin/zen
    echo "✅ Installed! You can now run: zen hello"
    exit 0
fi

### --- Self-Uninstaller ---
if [[ "$APP" == "uninstall-self" ]]; then
    echo "🧹 Removing zen from /usr/local/bin..."
    sudo rm -f /usr/local/bin/zen
    echo "✅ Removed zen."
    exit 0
fi

### --- Hello Command ---
if [[ "$APP" == "hello" ]]; then
    echo "👋 Hello from zen! ✅"
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

### --- Function: Docker install/uninstall ---
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

### --- Function: System Update ---
sys_update() {
    echo "⬆️ Updating system..."
    sudo apt update && sudo apt upgrade -y
    echo "🔧 Installing helper tools..."
    sudo apt install -y gnome-keyring wget curl git unzip htop
    echo "✅ System updated."
}

### --- Function: Webtop ---
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

### --- Main Dispatcher ---
case "$APP" in
    autodel) autodel "$ACTION" ;;
    docker) docker_manage "$ACTION" ;;
    update) sys_update ;;
    webtop) webtop_manage "$ACTION" ;;
    *) 
        echo "🔧 zen - Available commands:"
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
