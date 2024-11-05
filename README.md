# Talos Cluster Management Tools

This repository contains a Makefile and associated scripts for managing Talos Kubernetes clusters. It provides a streamlined interface for common cluster operations including initialization, deployment, node management, and configuration.

## Prerequisites

Before using these tools, ensure you have the following dependencies installed:
- `talosctl` (Talos CLI tool)
- `kubectl` (Kubernetes CLU tool)
- Other dependencies (checked by `make deps`)

## Directory Structure

```
.
├── clusters/          # Contains cluster-specific configurations
├── scripts/          # Contains operational scripts
└── Makefile         # Main interface for cluster operations
```

## Available Commands

### Basic Operations

- `make deps`
  - Checks system dependencies required for cluster operations
  - Runs the dependency verification script

- `make init`
  - Starts an interactive cluster initialization process
  - Must be run before creating a new cluster

- `make deploy <cluster-name>`
  - Deploys a new Talos cluster with the specified name
  - Example: `make deploy production`

- `make kubeconfig <cluster-name>`
  - Generates a kubeconfig file for the specified cluster
  - Saves the config to `clusters/<cluster-name>/kubeconfig`

### Node Management

- `make add-node <cluster-name> <node-type> <node-ip>`
  - Adds a new node to an existing cluster
  - `node-type` can be either `controlplane` or `worker`
  - Example: `make add-node production worker 192.168.1.100`

- `make remove-node <cluster-name> <node-ip>`
  - Removes a node from the specified cluster
  - Example: `make remove-node production 192.168.1.100`

### Cluster Maintenance

- `make reset-cluster <cluster-name>`
  - Resets all nodes in the specified cluster
  - Use with caution - this will destroy all data on the cluster

- `make apply <cluster-name> <node-ip> <patch-file>`
  - Applies configuration patches to specific nodes
  - Example: `make apply production 192.168.1.100 label.yaml`

## Usage Examples

1. Initialize a new cluster:
```bash
make init
```

2. Deploy a cluster named "staging":
```bash
make deploy staging
```

3. Add a worker node:
```bash
make add-node staging worker 192.168.1.101
```

4. Generate kubeconfig for accessing the cluster:
```bash
make kubeconfig staging
```

## Error Handling

The Makefile includes various error checks:
- Verifies cluster directory existence before operations
- Validates required parameters for each command
- Checks for the presence of necessary configuration files

## Notes

- All cluster-specific configurations and data are stored in the `clusters/<cluster-name>` directory
- The Makefile uses `/bin/bash` as the default shell for better script compatibility
- Make sure to run `make deps` before initial use to verify system requirements
- Always backup important data before running destructive operations like `reset-cluster`

## Getting Help

Run `make help` to see a list of available commands and their descriptions.
