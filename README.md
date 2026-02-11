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
Usage: monitoring-installer.sh [--1|--2|--3|--4|--5|--6|--node|--help]

Monitoring Server (central):
   --1      Installs Prometheus
   --2      Installs Grafana
   --4      Installs AvalancheGo Grafana dashboards
   --5      Installs Loki (log aggregation server)

Avalanche Nodes (each node):
   --3      Installs node_exporter (metrics)
   --6      Installs Promtail (log shipper to Loki)

All-in-one:
   --node   Runs steps 1, 2, 3, 4, and 6 (full single-node setup)
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

### Configure Prometheus Targets

Edit `/etc/prometheus/prometheus.yml` on your monitoring server to scrape all nodes:

```yaml
scrape_configs:
  - job_name: 'avalanchego'
    metrics_path: '/ext/metrics'
    static_configs:
      - targets: ['node1-ip:9650', 'node2-ip:9650']
        labels:
          node: 'node1'
      - targets: ['node2-ip:9650']
        labels:
          node: 'node2'

  - job_name: 'avalanchego-machine'
    static_configs:
      - targets: ['node1-ip:9100']
        labels:
          node: 'node1'
      - targets: ['node2-ip:9100']
        labels:
          node: 'node2'
```

Then restart Prometheus: `sudo systemctl restart prometheus`

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
