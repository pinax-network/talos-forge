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

    LOAD_BALANCER_IP=$(yq e '.load_balancer_ip' "$config_file") || handle_error "Failed to read load balancer IP"
    CONTROL_PLANE_IPS=$(yq e '.control_plane_ips | join(",")' "$config_file") || handle_error "Failed to read control plane IPs"
    WORKER_IPS=$(yq e '.worker_ips | join(",")' "$config_file") || handle_error "Failed to read worker IPs"

    log "Load Balancer IP: $LOAD_BALANCER_IP"
    log "Control Plane IPs: $CONTROL_PLANE_IPS"
    log "Worker IPS: $WORKER_IPS"
}

# Generate Talos configuration
generate_talos_config() {
    local talos_config_dir="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config"
    local base_patch="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/base-patch.yaml"
    local patches_dir="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/patches"

    # If talos-config directory exists, use existing configuration
    if [ -d "$talos_config_dir" ] && [ -f "${talos_config_dir}/controlplane.yaml" ]; then
        log "Found existing Talos configuration, using it for deployment"
        return 0
    fi

    # If no existing config, generate new one
    mkdir -p "$talos_config_dir" || handle_error "Failed to create talos-config directory"
    mkdir -p "$patches_dir" || handle_error "Failed to create patches directory"

    # Create base config patch if it doesn't exist
    if [ ! -f "$base_patch" ]; then
        log "Creating base configuration patch"
        cat > "$base_patch" <<'EOF'
# Base patch content goes here
EOF
    fi

    # Collect all patch files
    local patch_files=("$base_patch")
    if [ -d "$patches_dir" ]; then
        while IFS= read -r -d '' patch_file; do
            log "Found additional patch: $patch_file"
            patch_files+=("$patch_file")
        done < <(find "$patches_dir" -name "*.yaml" -type f -print0 | sort -z)
    fi

    # Build the patch arguments for talosctl
    local patch_args=()
    for patch_file in "${patch_files[@]}"; do
        patch_args+=("--config-patch" "@${patch_file}")
    done

    log "Generating Talos configuration with ${#patch_files[@]} patches"
    talosctl gen config "${CLUSTER_NAME}" "https://${LOAD_BALANCER_IP}:443" \
        --output "${talos_config_dir}" \
        --output-types controlplane,worker,talosconfig \
        "${patch_args[@]}" || handle_error "Failed to generate Talos configuration"
}

# Apply configuration to control plane nodes
apply_control_plane_config() {
    local talos_config_dir="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config"
    IFS=',' read -ra cp_ips <<< "$CONTROL_PLANE_IPS"
    for ip in "${cp_ips[@]}"; do
        log "Applying to control plane node: $ip"
        talosctl --talosconfig "${talos_config_dir}/talosconfig" apply-config --insecure -n "$ip" \
            --file "${talos_config_dir}/controlplane.yaml" || handle_error "Failed to apply config to control plane node $ip"
    done
}

# Apply configuration to worker nodes
apply_worker_config() {
    local talos_config_dir="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config"
    IFS=',' read -ra w_ips <<< "$WORKER_IPS"
    for ip in "${w_ips[@]}"; do
        log "Applying to worker node: $ip"
        talosctl --talosconfig "${talos_config_dir}/talosconfig" apply-config --insecure -n "$ip" \
            --file "${talos_config_dir}/worker.yaml" || handle_error "Failed to apply config to worker node $ip"
    done
}

# Bootstrap the cluster with retries and delay
bootstrap_cluster() {
    local talos_config_dir="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config"
    local bootstrap_retry_count=5
    local bootstrap_delay=30

    log "Bootstrapping the cluster"
    local first_cp_ip=$(echo "$CONTROL_PLANE_IPS" | cut -d',' -f1)
    talosctl --talosconfig "${talos_config_dir}/talosconfig" config endpoint "$first_cp_ip"
    talosctl --talosconfig "${talos_config_dir}/talosconfig" config node "$first_cp_ip"

    for ((i=1; i<=bootstrap_retry_count; i++)); do
        log "Attempt $i to bootstrap cluster..."
        if talosctl --talosconfig "${talos_config_dir}/talosconfig" bootstrap --nodes "$first_cp_ip"; then
            log "Cluster bootstrap successful"
            break
        else
            if [ $i -eq $bootstrap_retry_count ]; then
                handle_error "Failed to bootstrap cluster after $bootstrap_retry_count attempts"
            fi
            log "Bootstrap attempt $i failed, retrying in $bootstrap_delay seconds..."
            sleep $bootstrap_delay
        fi
    done
}

# Wait for the cluster to be ready
wait_for_cluster() {
    local talos_config_dir="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/talos-config"
    local timeout=300  # 5 minutes
    local interval=10  # 10 seconds
    local first_cp_ip=$(echo "$CONTROL_PLANE_IPS" | cut -d',' -f1)

    log "Waiting for cluster to be ready..."
    local end=$((SECONDS + timeout))
    while [ $SECONDS -lt $end ]; do
        if talosctl --talosconfig "${talos_config_dir}/talosconfig" health --nodes "$first_cp_ip" >/dev/null 2>&1; then
            log "Cluster is ready!"
            return 0
        fi
        log "Waiting for cluster to be ready... ($(($end - SECONDS))s remaining)"
        sleep $interval
    done
    handle_error "Timeout waiting for cluster to be ready"
}

# Main script execution
main() {
    validate_environment
    read_cluster_config
    generate_talos_config
    apply_control_plane_config
    apply_worker_config
    bootstrap_cluster
    wait_for_cluster
    log "Deployment of cluster ${CLUSTER_NAME} completed successfully!"
}

# Run main
main "$@"