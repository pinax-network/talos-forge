#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Default values and constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${PROJECT_ROOT}/deployment.log"
}

# Function for error handling
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Function to validate environment
validate_environment() {
    # Ensure required variables are set
    : "${CLUSTER_NAME:?CLUSTER_NAME must be set}"
    
    if [ ! -d "${PROJECT_ROOT}/clusters/${CLUSTER_NAME}" ]; then
        handle_error "Cluster ${CLUSTER_NAME} not found"
    fi

    # Check for talosconfig
    if [ ! -f "${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config/talosconfig" ]; then
        handle_error "Talos config not found for cluster ${CLUSTER_NAME}"
    fi
}

# Read cluster configuration
read_cluster_config() {
    local config_file="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/cluster-config.yaml"
    log "Reading configuration from ${config_file}"
    if [ ! -f "$config_file" ]; then 
        handle_error "Cluster configuration not found for ${CLUSTER_NAME}"
    fi

    CONTROL_PLANE_IPS=$(yq e '.control_plane_ips | join(",")' "$config_file") || handle_error "Failed to read control plane IPs"
    WORKER_IPS=$(yq e '.worker_ips | join(",")' "$config_file") || handle_error "Failed to read worker IPs"

    log "Control Plane IPs: $CONTROL_PLANE_IPS"
    log "Worker IPs: $WORKER_IPS"
}

# Reset a single node with retries
reset_node() {
    local node_ip=$1
    local node_type=$2
    local talos_config="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config/talosconfig"
    local max_retries=3
    local retry_delay=5
    
    log "Starting reset process for ${node_type} node: ${node_ip}"

    for ((i=1; i<=max_retries; i++)); do
        log "Attempting reset for ${node_ip} (attempt ${i}/${max_retries})"
        if talosctl --talosconfig "$talos_config" reset \
            --graceful=false \
            --reboot=true \
            --system-labels-to-wipe STATE,EPHEMERAL \
            --nodes "$node_ip" \
            --timeout 90s 2>/dev/null; then
            log "Successfully reset ${node_type} node: ${node_ip}"
            return 0
        else
            if [ $i -lt $max_retries ]; then
                log "Failed to reset ${node_type} node: ${node_ip}, retrying in ${retry_delay} seconds..."
                sleep $retry_delay
            else
                log "Warning: Failed to reset ${node_type} node: ${node_ip} after all attempts."
            fi
        fi
    done
    return 1
}

# Reset worker nodes first
reset_workers() {
    local failed_nodes=0
    IFS=',' read -ra w_ips <<< "$WORKER_IPS"
    
    if [ ${#w_ips[@]} -eq 0 ]; then
        log "No worker nodes found"
        return 0
    fi
    
    log "Resetting worker nodes..."
    for ip in "${w_ips[@]}"; do
        if ! reset_node "$ip" "worker"; then
            ((failed_nodes++))
        fi
        sleep 10
    done
    
    if [ $failed_nodes -gt 0 ]; then
        log "Warning: Failed to reset ${failed_nodes} worker node(s)"
    fi
}

# Reset control plane nodes in proper order
reset_control_plane() {
    local failed_nodes=0
    IFS=',' read -ra cp_ips <<< "$CONTROL_PLANE_IPS"
    local primary_cp=${cp_ips[0]}
    
    if [ ${#cp_ips[@]} -eq 0 ]; then
        log "No control plane nodes found"
        return 0
    fi
    
    # First reset secondary control plane nodes
    if [ ${#cp_ips[@]} -gt 1 ]; then
        log "Resetting secondary control plane nodes..."
        for ((i=1; i<${#cp_ips[@]}; i++)); do
            if ! reset_node "${cp_ips[i]}" "control plane"; then
                ((failed_nodes++))
            fi
            sleep 10
        done
    fi

    # Reset primary control plane last
    log "Resetting primary control plane node..."
    if reset_node "$primary_cp" "primary control plane"; then
        log "Primary control plane node reset successfully"
    else
        log "Note: Final reset command to primary control plane may appear to fail - this is expected as the node shuts down"
    fi
    
    log "Waiting for nodes to fully reset..."
    sleep 30
}

# Main script execution
main() {
    log "Starting cluster destruction for ${CLUSTER_NAME}"
    validate_environment
    read_cluster_config
    
    log "Phase 1: Resetting worker nodes"
    reset_workers
    
    log "Phase 2: Resetting control plane nodes"
    reset_control_plane
    
    log "Cluster destruction completed. Please wait for nodes to fully reset before redeploying (recommended wait: 2-3 minutes)."
}

# Run main
main "$@"