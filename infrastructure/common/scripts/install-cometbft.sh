#!/bin/bash
set -euo pipefail

# install-cometbft.sh
# Install CometBFT (Tendermint BFT consensus engine)
# Compatible with Ubuntu 22.04 LTS

COMETBFT_VERSION="${COMETBFT_VERSION:-v1.0.1}"
INSTALL_DIR="/usr/local/bin"
TEMP_DIR="/tmp/cometbft-install"

echo "===================================="
echo "CometBFT Installation"
echo "Version: ${COMETBFT_VERSION}"
echo "===================================="

# Check if already installed
if command -v cometbft &> /dev/null; then
    CURRENT_VERSION=$(cometbft version 2>&1 | grep -oP '(?<=version: )[0-9.]+' || echo "unknown")
    echo "CometBFT already installed (version: ${CURRENT_VERSION})"
    echo "To reinstall, remove existing binary first: rm ${INSTALL_DIR}/cometbft"
    exit 0
fi

# Determine architecture
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)
        ARCH_SUFFIX="amd64"
        ;;
    aarch64|arm64)
        ARCH_SUFFIX="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture ${ARCH}"
        exit 1
        ;;
esac

OS="linux"
BINARY_NAME="cometbft_${COMETBFT_VERSION#v}_${OS}_${ARCH_SUFFIX}.tar.gz"
DOWNLOAD_URL="https://github.com/cometbft/cometbft/releases/download/${COMETBFT_VERSION}/${BINARY_NAME}"

echo "[1/4] Creating temporary directory..."
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

echo "[2/4] Downloading CometBFT ${COMETBFT_VERSION}..."
echo "URL: ${DOWNLOAD_URL}"
if ! curl -LO "${DOWNLOAD_URL}"; then
    echo "Error: Failed to download CometBFT"
    echo "Please check if version ${COMETBFT_VERSION} exists at:"
    echo "https://github.com/cometbft/cometbft/releases"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

echo "[3/4] Extracting and installing..."
tar -xzf "${BINARY_NAME}"
chmod +x cometbft
mv cometbft "${INSTALL_DIR}/"

echo "[4/4] Verifying installation..."
if command -v cometbft &> /dev/null; then
    INSTALLED_VERSION=$(cometbft version 2>&1 | head -n1)
    echo "✓ CometBFT installed successfully"
    echo "  ${INSTALLED_VERSION}"
else
    echo "Error: Installation verification failed"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

# Cleanup
echo "Cleaning up temporary files..."
cd /
rm -rf "${TEMP_DIR}"

echo "===================================="
echo "CometBFT installation complete!"
echo "===================================="
echo ""
echo "Next steps:"
echo "1. Initialize CometBFT: cometbft init"
echo "2. Configure genesis file and peers"
echo "3. Start CometBFT: systemctl start cometbft"
