#!/bin/bash
set -euo pipefail

# build-vote-server.sh
# Build zcash-vote-server from source
# Compatible with Ubuntu 22.04 LTS

REPO_URL="${VOTE_SERVER_REPO:-https://github.com/alchemydc/zcash-vote-server}"
BRANCH="${VOTE_SERVER_BRANCH:-main}"
INSTALL_DIR="/opt/zcash-vote"
USER="zcash-vote"

echo "===================================="
echo "zcash-vote-server Build"
echo "Repository: ${REPO_URL}"
echo "Branch: ${BRANCH}"
echo "===================================="

# Set HOME if not already set (startup script context)
export HOME="${HOME:-/root}"

# Load Rust environment if installed
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
    echo "✓ Loaded Rust environment from $HOME/.cargo/env"
elif [ -f /root/.cargo/env ]; then
    source /root/.cargo/env
    echo "✓ Loaded Rust environment from /root/.cargo/env"
fi

# Ensure Rust is available
if ! command -v cargo &> /dev/null; then
    echo "Error: Rust/Cargo not found. Please run install-base.sh first."
    exit 1
fi

# Switch to installation directory
echo "[1/6] Setting up installation directory..."
if [ ! -d "${INSTALL_DIR}" ]; then
    mkdir -p "${INSTALL_DIR}"
    chown ${USER}:${USER} "${INSTALL_DIR}"
fi

cd "${INSTALL_DIR}"

# Clone or update repository
echo "[2/6] Fetching source code..."
if [ -d "${INSTALL_DIR}/zcash-vote-server" ]; then
    echo "Repository already exists, updating..."
    cd zcash-vote-server
    sudo -u ${USER} git fetch origin
    sudo -u ${USER} git checkout "${BRANCH}"
    sudo -u ${USER} git pull origin "${BRANCH}"
else
    echo "Cloning repository..."
    sudo -u ${USER} git clone --branch "${BRANCH}" "${REPO_URL}" zcash-vote-server
    cd zcash-vote-server
fi

# Build release version
echo "[3/6] Building release binary (this may take several minutes)..."
export CARGO_HOME="${INSTALL_DIR}/.cargo"
sudo -u ${USER} -E cargo build --release

# Verify build
echo "[4/6] Verifying build..."
if [ ! -f "target/release/zcash-vote-server" ]; then
    echo "Error: Build failed - binary not found"
    exit 1
fi

echo "✓ Build successful"
ls -lh target/release/zcash-vote-server

# Create necessary directories
echo "[5/6] Creating application directories..."
sudo -u ${USER} mkdir -p "${INSTALL_DIR}/data"
sudo -u ${USER} mkdir -p "${INSTALL_DIR}/config"

# Copy default configuration if it doesn't exist
if [ ! -f "${INSTALL_DIR}/config/Rocket.toml" ]; then
    echo "[6/6] Creating default configuration..."
    cat > "${INSTALL_DIR}/config/Rocket.toml" <<'EOF'
[default]
address = "0.0.0.0"
port = 8000

[default.limits]
bytes = "64 kB"

[default.custom]
data_path = "/opt/zcash-vote/data"
db_path = "/opt/zcash-vote/vote.db"
cometbft_port = 26658
EOF
    chown ${USER}:${USER} "${INSTALL_DIR}/config/Rocket.toml"
    echo "✓ Default configuration created at ${INSTALL_DIR}/config/Rocket.toml"
else
    echo "[6/6] Configuration already exists, skipping..."
fi

echo "===================================="
echo "Build complete!"
echo "===================================="
echo ""
echo "Binary location: ${INSTALL_DIR}/zcash-vote-server/target/release/zcash-vote-server"
echo "Configuration:   ${INSTALL_DIR}/config/Rocket.toml"
echo "Data directory:  ${INSTALL_DIR}/data"
echo ""
echo "Next steps:"
echo "1. Initialize CometBFT"
echo "2. Configure systemd services"
echo "3. Start services"
