SHELL := /bin/bash
.PHONY: help deps init deploy kubeconfig reset-cluster add-node remove-node apply \
        %  # Add % to match any target name

########################################################################################
# Variables
########################################################################################

CLUSTERS_DIR := clusters
SCRIPTS_DIR := scripts

# Extract cluster name and other arguments from command line
MAKECMDGOALS ?= 

# Function to check if directory exists
define check_cluster_dir
	@if [ ! -d "$(CLUSTERS_DIR)/$(1)" ]; then \
		echo "Error: Cluster directory '$(CLUSTERS_DIR)/$(1)' does not exist"; \
		exit 1; \
	fi
endef

ifeq ($(word 1,$(MAKECMDGOALS)),deploy)
    CLUSTER_NAME := $(word 2,$(MAKECMDGOALS))
    ifeq ($(CLUSTER_NAME),)
        $(error Please specify a cluster name: make deploy <cluster-name>)
    endif
endif

ifeq ($(filter kubeconfig,$(MAKECMDGOALS)),kubeconfig)
    CLUSTER_NAME := $(word 2,$(MAKECMDGOALS))
    ifeq ($(CLUSTER_NAME),)
        $(error Please specify a cluster name: make kubeconfig <cluster-name>)
    endif
endif

ifeq ($(word 1,$(MAKECMDGOALS)),reset-cluster)
    CLUSTER_NAME := $(word 2,$(MAKECMDGOALS))
    ifeq ($(CLUSTER_NAME),)
        $(error Please specify a cluster name: make reset-cluster <cluster-name>)
    endif
endif

ifeq ($(word 1,$(MAKECMDGOALS)),add-node)
    CLUSTER_NAME := $(word 2,$(MAKECMDGOALS))
    NODE_TYPE := $(word 3,$(MAKECMDGOALS))
    NODE_IP := $(word 4,$(MAKECMDGOALS))
    ifeq ($(CLUSTER_NAME),)
        $(error Please specify a cluster name: make add-node <cluster-name> <node-type> <node-ip>)
    endif
    ifeq ($(NODE_TYPE),)
        $(error Please specify the node type: make add-node <cluster-name> <node-type> <node-ip> (e.g., controlplane or worker))
    endif
    ifeq ($(NODE_IP),)
        $(error Please specify the node IP: make add-node <cluster-name> <node-type> <node-ip>)
    endif
endif

ifeq ($(word 1,$(MAKECMDGOALS)),remove-node)
    CLUSTER_NAME := $(word 2,$(MAKECMDGOALS))
    NODE_IP := $(lastword $(MAKECMDGOALS))
endif

ifeq ($(word 1,$(MAKECMDGOALS)),apply)
    CLUSTER_NAME := $(word 2,$(MAKECMDGOALS))
    NODE_IP := $(word 3,$(MAKECMDGOALS))
    PATCH_FILE := $(word 4,$(MAKECMDGOALS))
    ifeq ($(CLUSTER_NAME),)
        $(error Please specify a cluster name: make apply <cluster-name> <node-ip> <patch-file>)
    endif
    ifeq ($(NODE_IP),)
        $(error Please specify the node IP: make apply <cluster-name> <node-ip> <patch-file>)
    endif
    ifeq ($(PATCH_FILE),)
        $(error Please specify the patch file: make apply <cluster-name> <node-ip> <patch-file>)
    endif
endif

########################################################################################
# Targets
########################################################################################

help: ## Display this help message
	@echo "Usage:"
	@echo "  make deps                        # Check system dependencies"
	@echo "  make init                        # Interactive cluster initialization"
	@echo "  make deploy <cluster-name>       # Deploy Talos cluster"
	@echo "  make kubeconfig <cluster-name>   # Generate Kubeconfig"
	@echo "  make reset-cluster <cluster-name> # Reset Talos cluster nodes"
	@echo "  make add-node <cluster-name> <node-type> <node-ip> # Add a node to the cluster"
	@echo "  make remove-node <cluster-name> <node-ip>          # Remove a node from the cluster"
	@echo "  make apply <cluster-name> <node-ip> <patch-file>   # Apply patches to the specified cluster"

deps: ## Check system dependencies
	@./$(SCRIPTS_DIR)/check-deps.sh


init: deps ## Interactive cluster initialization
	@./$(SCRIPTS_DIR)/init-cluster.sh

deploy: ## Deploy Talos cluster
	$(call check_cluster_dir,$(CLUSTER_NAME))
	@CLUSTER_NAME=$(CLUSTER_NAME) ./$(SCRIPTS_DIR)/deploy-cluster.sh

kubeconfig: ## Generate Kubeconfig
	$(call check_cluster_dir,$(CLUSTER_NAME))
	@if [ ! -f "$(CLUSTERS_DIR)/$(CLUSTER_NAME)/talos-config/talosconfig" ]; then \
		echo "Error: talosconfig not found for cluster '$(CLUSTER_NAME)'"; \
		exit 1; \
	fi
	@talosctl --talosconfig "$(CLUSTERS_DIR)/$(CLUSTER_NAME)/talos-config/talosconfig" kubeconfig "$(CLUSTERS_DIR)/$(CLUSTER_NAME)/kubeconfig"
	@echo "✅ Kubeconfig saved to $(CLUSTERS_DIR)/$(CLUSTER_NAME)/kubeconfig"

reset-cluster: ## Reset all nodes in the specified Talos cluster
	$(call check_cluster_dir,$(CLUSTER_NAME))
	@CLUSTER_NAME=$(CLUSTER_NAME) ./$(SCRIPTS_DIR)/reset-cluster.sh
	@echo "Reset process initiated for cluster $(CLUSTER_NAME). Check the logs for details."

add-node: ## Add a node to the cluster
	$(call check_cluster_dir,$(CLUSTER_NAME))
	@CLUSTER_NAME=$(CLUSTER_NAME) \
	NODE_TYPE=$(NODE_TYPE) \
	NODE_IP=$(NODE_IP) \
	./$(SCRIPTS_DIR)/add-node.sh
	@echo "Node with IP $(NODE_IP) added to cluster $(CLUSTER_NAME)"

remove-node: ## Remove a node from the cluster
	@CLUSTER_NAME=$(CLUSTER_NAME) NODE_IP=$(NODE_IP) ./$(SCRIPTS_DIR)/remove-node.sh

apply:
	@if [ -z "$(word 2,$(MAKECMDGOALS))" ] || [ -z "$(word 3,$(MAKECMDGOALS))" ] || [ -z "$(word 4,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make apply <cluster_name> <node_ip> <patch_file>"; \
		echo "Example: make apply demo 165.227.2.62 label.yaml"; \
		exit 1; \
	fi
	./scripts/apply-patch.sh $(word 2,$(MAKECMDGOALS)) $(word 3,$(MAKECMDGOALS)) $(word 4,$(MAKECMDGOALS))

# Catch-all target to handle argument passing
%:
	@: