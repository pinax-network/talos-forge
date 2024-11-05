#!/bin/bash

set -eo pipefail

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if required variables are set
if [ -z "${CLUSTER_NAME:-}" ]; then
    log "❌ Error: CLUSTER_NAME environment variable is not set"
    exit 1
fi

if [ -z "${NODE_IP:-}" ]; then
    log "❌ Error: NODE_IP environment variable is not set"
    exit 1
fi

TALOSCONFIG="clusters/${CLUSTER_NAME}/talos-config/talosconfig"
KUBECONFIG="clusters/${CLUSTER_NAME}/kubeconfig"
CONFIG_FILE="clusters/${CLUSTER_NAME}/cluster-config.yaml"

# Reset the node with specific labels to wipe
log "🔄 Resetting node ${NODE_IP}..."
OUTPUT=$(talosctl --talosconfig="$TALOSCONFIG" reset --system-labels-to-wipe STATE,EPHEMERAL --graceful=false --reboot -n "$NODE_IP" || true)
if echo "$OUTPUT" | grep -q "post check passed"; then
    log "✅ Node reset successful and rebooting"
fi

# Get node name from IP
NODE_NAME=$(kubectl --kubeconfig="$KUBECONFIG" get nodes -o wide | grep "$NODE_IP" | awk '{print $1}' || true)

# Remove from Kubernetes if node exists
if [ -n "$NODE_NAME" ]; then
    log "🗑️  Removing node ${NODE_NAME} from Kubernetes..."
    kubectl --kubeconfig="$KUBECONFIG" delete node "$NODE_NAME" || true
fi

# Update cluster-config.yaml - using direct file modification
log "📝 Updating cluster configuration..."
yq -i eval "(.control_plane_ips -= [\"$NODE_IP\"]) | (.worker_ips -= [\"$NODE_IP\"])" "$CONFIG_FILE"

log "✅ Node removal completed"
exit 0