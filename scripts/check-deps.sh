#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function for logging
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for required commands
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        if [ "$cmd" = "talosctl" ]; then
            echo ""
            log "talosctl not found. Installation instructions:"
            echo ""
            echo "Please visit: https://www.talos.dev/v1.8/talos-guides/install/talosctl/"
            echo ""
            echo "Quick installation methods:"
            echo ""
            echo "1. Using curl (Linux/macOS):"
            echo "   curl -Lo /usr/local/bin/talosctl https://github.com/siderolabs/talos/releases/latest/download/talosctl-\$(uname -s | tr \"[:upper:]\" \"[:lower:]\")-amd64"
            echo "   chmod +x /usr/local/bin/talosctl"
            echo ""
            echo "2. Using Homebrew (macOS):"
            echo "   brew install siderlabs/talos/talosctl"
            echo ""
            error "$cmd is not installed and is required"
        else
            error "$cmd is not installed and is required"
        fi
    else
        log "$cmd is installed ($(command -v "$cmd"))"
    fi
}

# Main dependency check
main() {
    log "Checking system dependencies..."
    
    # Check essential commands
    check_command curl
    check_command git
    check_command yq
    check_command talosctl
    
    log "All dependencies are satisfied"
}

main "$@"