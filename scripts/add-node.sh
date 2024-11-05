#!/bin/bash

set -euo pipefail

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a node IP is already in use
check_node_ip() {
    local ip=$1
    local talosconfig=$2
    
    if talosctl --talosconfig "$talosconfig" get members -n "$ip" &>/dev/null; then
        return 0  # IP is in use
    fi
    return 1  # IP is not in use
}

# Ensure required environment variables
: "${CLUSTER_NAME:?CLUSTER_NAME must be set}"
: "${NODE_TYPE:?NODE_TYPE must be set (worker or controlplane)}"
: "${NODE_IP:?NODE_IP must be set}"

CONFIG_FILE="clusters/${CLUSTER_NAME}/cluster-config.yaml"
TALOS_CONFIG="clusters/${CLUSTER_NAME}/talos-config/talosconfig"
NODE_CONFIG_FILE="clusters/${CLUSTER_NAME}/talos-config/${NODE_TYPE}.yaml"
KUBECONFIG="clusters/${CLUSTER_NAME}/kubeconfig"

# Update cluster-config.yaml
log "📝 Updating cluster configuration..."
if [ "$NODE_TYPE" = "controlplane" ]; then
    yq -i eval ".control_plane_ips += [\"$NODE_IP\"]" "$CONFIG_FILE"
else
    yq -i eval ".worker_ips += [\"$NODE_IP\"]" "$CONFIG_FILE"
fi

# Apply the configuration to add the node
log "🔄 Applying Talos configuration to node..."
talosctl --talosconfig "$TALOS_CONFIG" apply-config --insecure --nodes "$NODE_IP" -f "$NODE_CONFIG_FILE"

log "✅ Node addition process completed"