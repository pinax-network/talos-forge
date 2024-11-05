#!/bin/bash

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

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local var_name="$2"
    local validate_func="$3"
    local values=()

    while true; do
        read -p "$prompt: " value
        if [ -z "$value" ]; then
            echo "Value cannot be empty. Please try again."
            continue
        fi
        
        if [ -n "$validate_func" ]; then
            if $validate_func "$value"; then
                values+=("$value")
                break
            fi
        else
            values+=("$value")
            break
        fi
    done

    printf -v "$var_name" "%s" "${values[*]}"
}

# Function to validate IP address
validate_ip() {
    local ips=($@)
    local is_valid=true

    for ip in "${ips[@]}"; do
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            for i in {1..4}; do
                if [ $(echo "$ip" | cut -d. -f$i) -gt 255 ]; then
                    echo "Invalid IP address format: $ip. Please use x.x.x.x format where x is between 0-255."
                    is_valid=false
                    break
                fi
            done
        else
            echo "Invalid IP address format: $ip. Please use x.x.x.x format."
            is_valid=false
            break
        fi
    done

    if $is_valid; then
        return 0
    else
        return 1
    fi
}

# Function to validate number input
validate_number() {
    local num=$1
    if [[ $num =~ ^[1-9][0-9]*$ ]]; then
        return 0
    else
        echo "Please enter a valid number greater than 0."
        return 1
    fi
}

# Function to create cluster configuration
create_cluster_config() {
    local cluster_name="$1"
    local lb_ip="$2"
    local cp_ips="$3"
    local worker_ips="$4"
    local config_dir="${PROJECT_ROOT}/clusters/${cluster_name}"
    local config_file="${config_dir}/cluster-config.yaml"

    mkdir -p "$config_dir"

    # Create cluster configuration
    cat > "$config_file" << EOF
cluster_name: ${cluster_name}
load_balancer_ip: ${lb_ip}
control_plane_ips:
$(echo "$cp_ips" | tr ',' '\n' | sed 's/^/  - /')
worker_ips:
$(echo "$worker_ips" | tr ',' '\n' | sed 's/^/  - /')
EOF

    log "Configuration saved to: $config_file"
}

# Main initialization function
initialize_cluster() {
    echo "Welcome to Talos Cluster Initialization"
    echo "--------------------------------------"
    echo ""

    # Get cluster name
    get_input "Enter cluster name" CLUSTER_NAME

    # Get Load Balancer IP
    get_input "Enter Load Balancer IP" LB_IP validate_ip

    # Get Control Plane nodes
    get_input "Enter control plane node IPs (separated by spaces)" CP_IPS validate_ip
    CP_IPS=$(echo "$CP_IPS" | tr ' ' ',')

    # Get Worker nodes
    get_input "Enter worker node IPs (separated by spaces)" WORKER_IPS validate_ip
    WORKER_IPS=$(echo "$WORKER_IPS" | tr ' ' ',')

    # Create configuration
    create_cluster_config "$CLUSTER_NAME" "$LB_IP" "$CP_IPS" "$WORKER_IPS"

    # Ask about next steps
    echo ""
    read -p "Would you like to generate templates now? [y/N]: " generate_templates
    if [[ $generate_templates =~ ^[Yy]$ ]]; then
        CLUSTER_NAME=$CLUSTER_NAME ./scripts/template-talos.sh
    fi

    echo ""
    echo "Initialization complete!"
    echo "You can now run:"
    echo "  make deploy $CLUSTER_NAME    # To deploy the cluster"
}

# Run initialization
initialize_cluster