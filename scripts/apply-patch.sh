#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Default values and constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Enable command printing
set -x

# Ensure required arguments
if [[ -z "$1" || -z "$2" || -z "$3" ]]; then
    log "ERROR: Usage: $0 <cluster_name> <node_ip> <patch_file>"
    log "Example: $0 demo 165.227.2.62 label.yaml"
    exit 1
fi

CLUSTER_NAME="$1"
NODE_IP="$2"
PATCH_FILE="$3"

# Construct paths
TALOS_CONFIG="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config/talosconfig"
PATCH_PATH="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/patches/${PATCH_FILE}"

# Verify files exist
if [ ! -f "$TALOS_CONFIG" ]; then
    log "ERROR: Talos config not found at ${TALOS_CONFIG}"
    exit 1
fi

if [ ! -f "$PATCH_PATH" ]; then
    log "ERROR: Patch file not found at ${PATCH_PATH}"
    exit 1
fi

# Print the current directory and files for debugging
pwd
ls -la "${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config/"
ls -la "${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/patches/"

# Try to patch using machineconfig instead of apply-config
log "Attempting to patch node $NODE_IP in cluster $CLUSTER_NAME"
talosctl --talosconfig "$TALOS_CONFIG" patch machineconfig \
    --nodes "$NODE_IP" \
    --patch "@${PATCH_PATH}"

# If the above fails, try apply-config as fallback
if [ $? -ne 0 ]; then
    log "Patch attempt failed, trying apply-config..."
    talosctl --talosconfig "$TALOS_CONFIG" apply-config \
        --nodes "$NODE_IP" \
        -f "$PATCH_PATH"
fi

log "Operation completed for node $NODE_IP in cluster $CLUSTER_NAME"