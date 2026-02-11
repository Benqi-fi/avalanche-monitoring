# Avalanche Node Monitoring

Grafana dashboards and installer script for monitoring Avalanche nodes.

## Quick Start

```bash
curl -sSfLO https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/monitoring-installer.sh
chmod +x monitoring-installer.sh
./monitoring-installer.sh --help
```

## Installation Options

```
Usage: monitoring-installer.sh [--1|--2|--3|--4|--5|--6|--node|--add-node|--help]

Monitoring Server (central):
   --1          Installs Prometheus
   --2          Installs Grafana
   --4          Installs AvalancheGo Grafana dashboards
   --5          Installs Loki (log aggregation server)
   --add-node   Adds a remote Avalanche node to Prometheus scrape targets

Avalanche Nodes (each node):
   --3          Installs node_exporter (metrics)
   --6          Installs Promtail (log shipper to Loki)

All-in-one:
   --node       Runs steps 1, 2, 3, 4, and 6 (full single-node setup)
```

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Avalanche      │     │  Avalanche      │     │  Avalanche      │
│  Node 1         │     │  Node 2         │     │  Node N         │
│  + node_exporter│     │  + node_exporter│     │  + node_exporter│
│  + promtail     │     │  + promtail     │     │  + promtail     │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │  Monitoring Server     │
                    │  - Prometheus (:9090)  │
                    │  - Loki (:3100)        │
                    │  - Grafana (:3000)     │
                    └────────────────────────┘
```

## Setup Guide

### Single-Node Setup (All-in-One)

If your Avalanche node and monitoring stack run on the same machine:

```bash
./monitoring-installer.sh --node   # Installs Prometheus, Grafana, node_exporter, dashboards, and Promtail
```

### Monitoring Server Setup

Run these on your central monitoring server:

```bash
./monitoring-installer.sh --1    # Install Prometheus
./monitoring-installer.sh --2    # Install Grafana
./monitoring-installer.sh --5    # Install Loki (optional, for logs)
./monitoring-installer.sh --4    # Install dashboards
```

### Avalanche Node Setup

Run these on **each** Avalanche node you want to monitor:

```bash
./monitoring-installer.sh --3    # Install node_exporter (metrics)
./monitoring-installer.sh --6    # Install Promtail (optional, for logs)
```

When running `--6`, you'll be prompted for:
- Loki server address (your monitoring server IP)
- Node name (e.g., `aws-validator-01`)
- Network identifier (e.g., `mainnet`)

### Add Remote Nodes to Prometheus

On your monitoring server, run `--add-node` for each remote Avalanche node:

```bash
./monitoring-installer.sh --add-node
```

You'll be prompted for:
- **IP address** of the remote node
- **Node name** (e.g., `aws-validator-01`)
- **Cloud/provider label** (e.g., `aws`, `gcp`)

The command automatically adds the node to three Prometheus scrape jobs:
- `avalanchego` — AvalancheGo API metrics (port 9650)
- `avalanchego-machine` — node_exporter metrics (port 9100)
- `avalanche_nodes` — remote Prometheus metrics (port 9090)

If a job doesn't exist yet, it will be created. A backup of `prometheus.yml` is saved before each change.

## Dashboards

| Dashboard | Description |
|-----------|-------------|
| Main | Overview with health checks, block heights, peers |
| C-Chain | EVM metrics, gas, transactions, block processing |
| P-Chain | Platform chain consensus and staking |
| X-Chain | Exchange chain metrics |
| Database | LevelDB operations and latency |
| Machine | CPU, memory, disk, network I/O |
| Network | Peer connections, bandwidth, message rates |
| Logs | Log aggregation (requires Loki) |

## Multi-Node Support

All dashboards include a **Node** dropdown to filter by node. Select one or multiple nodes to compare metrics side-by-side.

## Full Setup Guide

For complete setup instructions, see the [Avalanche monitoring documentation](https://docs.avax.network/nodes/maintain/setting-up-node-monitoring).
