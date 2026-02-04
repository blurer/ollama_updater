#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="/etc/systemd/system/ollama.service"
BACKUP_FILE="$SCRIPT_DIR/ollama.service.bak"
GITHUB_API="https://api.github.com/repos/ollama/ollama/releases"

MODE="stable"  # default: stable, check, pre-release

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pre-release|-p)
            MODE="pre-release"
            shift
            ;;
        --check|-c)
            MODE="check"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--check|-c] [--pre-release|-p]"
            exit 1
            ;;
    esac
done

# --- Helper functions ---

get_current_version() {
    if command -v ollama &>/dev/null; then
        ollama --version 2>/dev/null | grep -oP '\d+\.\d+\.\S+' || echo "unknown"
    else
        echo "not installed"
    fi
}

# Detect JSON parsing tool
if command -v jq &>/dev/null; then
    JSON_TOOL="jq"
elif command -v python3 &>/dev/null; then
    JSON_TOOL="python3"
else
    JSON_TOOL="none"
fi

# Fetch releases JSON from GitHub
fetch_releases() {
    curl -fsSL "$GITHUB_API" 2>/dev/null
}

# Extract latest stable release info
get_latest_stable() {
    local releases="$1"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        echo "$releases" | jq -r '[.[] | select(.prerelease == false and .draft == false)] | first | "\(.tag_name)\n\(.body)"'
    elif [[ "$JSON_TOOL" == "python3" ]]; then
        echo "$releases" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for r in data:
    if not r.get("prerelease") and not r.get("draft"):
        print(r["tag_name"])
        print(r.get("body", ""))
        break
'
    else
        echo "Error: neither jq nor python3 found. Install one of them to use this feature." >&2
        exit 1
    fi
}

# Extract latest pre-release info
get_latest_prerelease() {
    local releases="$1"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        echo "$releases" | jq -r '[.[] | select(.prerelease == true and .draft == false)] | first | "\(.tag_name)\n\(.body)"'
    elif [[ "$JSON_TOOL" == "python3" ]]; then
        echo "$releases" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for r in data:
    if r.get("prerelease") and not r.get("draft"):
        print(r["tag_name"])
        print(r.get("body", ""))
        break
'
    else
        echo "Error: neither jq nor python3 found. Install one of them to use this feature." >&2
        exit 1
    fi
}

# Detect system architecture for download
get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       echo "$arch" ;;
    esac
}

# Install a pre-release by downloading directly from GitHub release assets
install_prerelease() {
    local tag="$1"
    local arch
    arch=$(get_arch)
    local asset_name="ollama-linux-${arch}.tar.zst"
    local download_url="https://github.com/ollama/ollama/releases/download/${tag}/${asset_name}"
    local install_dir="/usr/local"

    if ! command -v zstd &>/dev/null; then
        echo "Error: zstd is required to extract pre-release archives."
        echo "Install it with: sudo dnf install zstd  (or apt-get install zstd)"
        exit 1
    fi

    echo "Downloading ${asset_name} from GitHub..."
    # Clean old libs and extract new ones, same as the official install script
    sudo rm -rf "${install_dir}/lib/ollama"
    sudo install -o0 -g0 -m755 -d "${install_dir}/bin"
    sudo install -o0 -g0 -m755 -d "${install_dir}/lib/ollama"
    curl -fSL "$download_url" | zstd -d | sudo tar -xf - -C "${install_dir}"
    echo "Installed ollama ${tag} to ${install_dir}"
}

# --- Main logic ---

# Always show current version
CURRENT_VERSION=$(get_current_version)
echo "Current installed version: $CURRENT_VERSION"
echo ""

if [[ "$MODE" == "check" ]]; then
    echo "Fetching release info from GitHub..."
    RELEASES=$(fetch_releases)

    STABLE_INFO=$(get_latest_stable "$RELEASES")
    STABLE_TAG=$(echo "$STABLE_INFO" | head -n1)
    STABLE_NOTES=$(echo "$STABLE_INFO" | tail -n+2)

    PRE_INFO=$(get_latest_prerelease "$RELEASES")
    PRE_TAG=$(echo "$PRE_INFO" | head -n1)
    PRE_NOTES=$(echo "$PRE_INFO" | tail -n+2)

    echo "========================================="
    echo "Latest stable release: $STABLE_TAG"
    echo "========================================="
    if [[ -n "$STABLE_NOTES" ]]; then
        echo "$STABLE_NOTES"
    fi
    echo ""
    echo "========================================="
    echo "Latest pre-release: $PRE_TAG"
    echo "========================================="
    if [[ -n "$PRE_NOTES" ]]; then
        echo "$PRE_NOTES"
    fi

    exit 0
fi

if [[ "$MODE" == "pre-release" ]]; then
    echo "Fetching pre-release info from GitHub..."
    RELEASES=$(fetch_releases)

    PRE_INFO=$(get_latest_prerelease "$RELEASES")
    PRE_TAG=$(echo "$PRE_INFO" | head -n1)
    PRE_NOTES=$(echo "$PRE_INFO" | tail -n+2)

    if [[ -z "$PRE_TAG" || "$PRE_TAG" == "null" ]]; then
        echo "No pre-release found."
        exit 1
    fi

    echo "========================================="
    echo "Latest pre-release: $PRE_TAG"
    echo "========================================="
    if [[ -n "$PRE_NOTES" ]]; then
        echo "$PRE_NOTES"
    fi
    echo ""

    read -rp "Install pre-release $PRE_TAG? [y/N] " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
fi

# --- Install (stable or confirmed pre-release) ---

if [ ! -f "$SERVICE_FILE" ]; then
    echo "Error: $SERVICE_FILE not found"
    exit 1
fi

echo "Backing up $SERVICE_FILE..."
sudo cp "$SERVICE_FILE" "$BACKUP_FILE"

# Run the install
if [[ "$MODE" == "pre-release" ]]; then
    echo "Updating ollama to pre-release $PRE_TAG..."
    install_prerelease "$PRE_TAG"
else
    echo "Updating ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Restore the systemd service file
echo "Restoring systemd service file..."
sudo cp "$BACKUP_FILE" "$SERVICE_FILE"

# Reload and restart
echo "Reloading systemd and restarting ollama..."
sudo systemctl daemon-reload
sudo systemctl restart ollama

echo "Done. Ollama updated with original service config preserved."
