
#!/bin/bash
set -euo pipefail
# ─────────────────────────────────────────────
# install-vscode.sh — Install & run code-server
# Access VS Code in your browser on port 8080
# ─────────────────────────────────────────────

export DEBIAN_FRONTEND=noninteractive

# ── Helpers ───────────────────────────────────
log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

maybe_sudo() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

PORT=8080

# ── Generate a random password (16 chars) ─────
# Falls back to a uuid-style string if openssl unavailable
generate_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16
    else
        # POSIX-safe fallback using /dev/urandom
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
    fi
}

PASSWORD=$(generate_password)

# ── System update & dependency install ────────
log "Updating system and installing dependencies..."

if command -v apt-get >/dev/null 2>&1; then
    log "Detected apt-based system."
    maybe_sudo apt-get update -y
    maybe_sudo apt-get upgrade -y
    maybe_sudo apt-get install -y curl wget ufw

elif command -v dnf >/dev/null 2>&1; then
    log "Detected dnf-based system."
    maybe_sudo dnf upgrade -y --refresh
    maybe_sudo dnf install -y curl wget firewalld

elif command -v yum >/dev/null 2>&1; then
    log "Detected yum-based system."
    maybe_sudo yum update -y
    maybe_sudo yum install -y curl wget firewalld

elif command -v pacman >/dev/null 2>&1; then
    log "Detected pacman-based system."
    maybe_sudo pacman -Syu --noconfirm
    maybe_sudo pacman -S --noconfirm --needed curl wget

else
    err "No supported package manager found (apt/dnf/yum/pacman)."
fi

# ── Install code-server (skip if already present) ──
if command -v code-server >/dev/null 2>&1; then
    log "code-server is already installed: $(code-server --version | head -1)"
else
    log "Installing code-server..."
    curl -fsSL https://code-server.dev/install.sh | sh
fi

# ── Firewall configuration ────────────────────
# Only call the firewall tool that is actually present & active
log "Configuring firewall for port $PORT..."

if command -v ufw >/dev/null 2>&1 && maybe_sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    maybe_sudo ufw allow "$PORT/tcp"
    log "ufw: allowed $PORT/tcp"
elif command -v firewall-cmd >/dev/null 2>&1; then
    maybe_sudo systemctl start firewalld 2>/dev/null || true
    maybe_sudo firewall-cmd --add-port="$PORT/tcp" --permanent
    maybe_sudo firewall-cmd --reload
    log "firewalld: allowed $PORT/tcp"
else
    warn "No active firewall detected — skipping firewall configuration."
fi

# ── Stop any existing code-server owned by this user ──
log "Stopping any existing code-server process..."
# Target only THIS user's code-server, not system-wide
pkill -u "$(id -u)" -f "code-server" 2>/dev/null || true
sleep 1

# ── Launch code-server ────────────────────────
LOG_FILE="$HOME/code-server.log"
log "Starting code-server on port $PORT..."

PASSWORD="$PASSWORD" nohup code-server \
    --bind-addr "0.0.0.0:$PORT" \
    --auth password \
    > "$LOG_FILE" 2>&1 &

CS_PID=$!
disown "$CS_PID"   # Detach from shell so it survives terminal close

# ── Verify it actually started ─────────────────
log "Waiting for code-server to start (PID $CS_PID)..."
for i in {1..10}; do
    sleep 1
    if kill -0 "$CS_PID" 2>/dev/null; then
        log "code-server is running (attempt $i/10)."
        break
    fi
    if [ "$i" -eq 10 ]; then
        err "code-server failed to start. Check logs: $LOG_FILE"
    fi
done

# Double-check the port is actually listening
if command -v ss >/dev/null 2>&1; then
    ss -tlnp | grep -q ":$PORT" \
        || warn "Port $PORT not yet visible in ss output — may still be starting."
fi

# ── Detect public/local IP ────────────────────
IP=""
for svc in \
    "https://ifconfig.me" \
    "https://api.ipify.org" \
    "https://checkip.amazonaws.com"; do
    IP=$(curl -s --max-time 4 "$svc" 2>/dev/null | tr -d '[:space:]') && \
        [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
    IP=""
done

# Fall back to local IP if public IP detection failed
if [[ -z "$IP" ]]; then
    IP=$(hostname -I 2>/dev/null | awk '{print $1}') || IP="127.0.0.1"
    warn "Could not detect public IP; showing local IP."
fi

# ── Summary ───────────────────────────────────
echo ""
echo "=========================================="
echo "  VS Code Server is running!"
echo "  URL:      http://${IP}:${PORT}"
echo "  Password: ${PASSWORD}"
echo "  PID:      ${CS_PID}"
echo "  Logs:     tail -f ${LOG_FILE}"
echo "=========================================="
echo ""
warn "Save your password now — it will not be shown again."

