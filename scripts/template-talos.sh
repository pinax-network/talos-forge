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

# Function for error handling
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Function to validate environment
validate_environment() {
    # Ensure required variables are set
    : "${CLUSTER_NAME:?CLUSTER_NAME must be set}"
    
    # Ensure we're in the right directory structure
    if [ ! -d "${PROJECT_ROOT}/clusters" ]; then
        mkdir -p "${PROJECT_ROOT}/clusters"
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
generate_template_configs() {
    local cluster_dir="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}"
    local patches_dir="${cluster_dir}/patches"
    mkdir -p "$patches_dir" || handle_error "Failed to create directories"

    # Create base config patch for CNI and other required settings
    local base_patch="${cluster_dir}/base-patch.yaml"
    log "Creating base configuration patch"
    cat > "$base_patch" <<'EOF'
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
  inlineManifests:
    - name: cilium-install
      contents: |
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: cilium-install
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: cluster-admin
        subjects:
        - kind: ServiceAccount
          name: cilium-install
          namespace: kube-system
        ---
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: cilium-install
          namespace: kube-system
        ---
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: cilium-install
          namespace: kube-system
        spec:
          backoffLimit: 10
          template:
            metadata:
              labels:
                app: cilium-install
            spec:
              restartPolicy: OnFailure
              tolerations:
                - operator: Exists
                - effect: NoSchedule
                  operator: Exists
                - effect: NoExecute
                  operator: Exists
                - effect: PreferNoSchedule
                  operator: Exists
                - key: node-role.kubernetes.io/control-plane
                  operator: Exists
                  effect: NoSchedule
                - key: node-role.kubernetes.io/control-plane
                  operator: Exists
                  effect: NoExecute
                - key: node-role.kubernetes.io/control-plane
                  operator: Exists
                  effect: PreferNoSchedule
              affinity:
                nodeAffinity:
                  requiredDuringSchedulingIgnoredDuringExecution:
                    nodeSelectorTerms:
                      - matchExpressions:
                          - key: node-role.kubernetes.io/control-plane
                            operator: Exists
              serviceAccount: cilium-install
              serviceAccountName: cilium-install
              hostNetwork: true
              containers:
              - name: cilium-install
                image: quay.io/cilium/cilium-cli-ci:v0.16.16
                env:
                - name: KUBERNETES_SERVICE_HOST
                  valueFrom:
                    fieldRef:
                      apiVersion: v1
                      fieldPath: status.podIP
                - name: KUBERNETES_SERVICE_PORT
                  value: "6443"
                command:
                  - cilium
                  - install
                  - --namespace
                  - kube-system
                  - --set
                  - ipam.mode=kubernetes
                  - --set
                  - kubeProxyReplacement=true
                  - --set
                  - securityContext.capabilities.ciliumAgent={CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}
                  - --set
                  - securityContext.capabilities.cleanCiliumState={NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}
                  - --set
                  - cgroup.autoMount.enabled=false
                  - --set
                  - cgroup.hostRoot=/sys/fs/cgroup
                  - --set
                  - k8sServiceHost=localhost
                  - --set
                  - k8sServicePort=7445
EOF

    # Generate Talos configurations
    log "Generating Talos configuration"
    local talos_config_dir="${cluster_dir}/talos-config"
    mkdir -p "$talos_config_dir"
    
    talosctl gen config "${CLUSTER_NAME}" "https://${LOAD_BALANCER_IP}:443" \
        --output "${talos_config_dir}" \
        --output-types controlplane,worker,talosconfig \
        --config-patch @"${base_patch}" || handle_error "Failed to generate Talos configuration"

    log "Configuration generation completed successfully"
    echo ""
    echo "Configurations generated in: clusters/${CLUSTER_NAME}/"
    echo "  ├── cluster-config.yaml    # Cluster configuration"
    echo "  ├── base-patch.yaml       # Base CNI configuration"
    echo "  ├── patches/              # Directory for your custom patches"
    echo "  └── talos-config/         # Generated configurations"
    echo "      ├── controlplane.yaml"
    echo "      ├── worker.yaml"
    echo "      └── talosconfig"
}

# Main script execution
main() {
    validate_environment
    read_cluster_config
    generate_template_configs
}

# Run main
main "$@"