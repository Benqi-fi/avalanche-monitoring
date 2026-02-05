#!/bin/bash
# Does a multi-step installation of Prometheus, Grafana, node_exporter and Avalanche dashboards
# Intended for non-technical validators, assumes running on compatible Ubuntu.

#stop on errors
set -e

#helper function that prints usage
usage () {
  echo "Usage: $0 [--1|--2|--3|--4|--5|--6|--help]"
  echo ""
  echo "Options:"
  echo "   --help   Shows this message"
  echo ""
  echo "   Monitoring Server (central):"
  echo "   --1      Step 1: Installs Prometheus"
  echo "   --2      Step 2: Installs Grafana"
  echo "   --4      Step 4: Installs AvalancheGo Grafana dashboards"
  echo "   --5      Step 5: Installs Loki (log aggregation server)"
  echo ""
  echo "   Avalanche Nodes (each node):"
  echo "   --3      Step 3: Installs node_exporter (metrics)"
  echo "   --6      Step 6: Installs Promtail (log shipper to Loki)"
  echo ""
  echo "Run without any options, script will download and install latest version of AvalancheGo dashboards."
}

#helper function to check for presence of required commands, and install if missing
check_reqs () {
  if ! command -v curl &> /dev/null
  then
      echo "curl could not be found, will install..."
      sudo apt-get install curl -y
  fi
  if ! command -v wget &> /dev/null
  then
      echo "wget could not be found, will install..."
      sudo apt-get install wget -y
  fi
}

#helper function to check for supported environment
get_environment() {
  echo "Checking environment..."
  check_reqs
  foundArch="$(uname -m)"                         #get system architecture
  foundOS="$(uname)"                              #get OS
  if [ "$foundOS" != "Linux" ]; then
    #sorry, don't know you.
    echo "Unsupported operating system: $foundOS!"
    echo "Exiting."
    exit
  fi
  if [ "$foundArch" = "aarch64" ]; then
    getArch="arm64"                               #we're running on arm arch (probably RasPi)
    echo "Found arm64 architecture..."
  elif [ "$foundArch" = "x86_64" ]; then
    getArch="amd64"                               #we're running on intel/amd
    echo "Found amd64 architecture..."
  else
    #sorry, don't know you.
    echo "Unsupported architecture: $foundArch!"
    echo "Exiting."
    exit
  fi
}

install_prometheus() {
  echo "AvalancheGo monitoring installer"
  echo "--------------------------------"
  echo "STEP 1: Installing Prometheus"
  echo
  get_environment
  check_reqs
  mkdir -p /tmp/avalanche-monitoring-installer/prometheus
  cd /tmp/avalanche-monitoring-installer/prometheus

  promFileName="$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep -o "http.*linux-$getArch\.tar\.gz")"
  if [[ $(wget -S --spider "$promFileName"  2>&1 | grep 'HTTP/1.1 200 OK') ]]; then
    echo "Prometheus install archive found: $promFileName"
  else
    echo "Unable to find Prometheus install archive. Exiting."
    exit
  fi
  echo "Attempting to download: $promFileName"
  wget -nv --show-progress -O prometheus.tar.gz "$promFileName"
  mkdir -p prometheus
  tar xvf prometheus.tar.gz -C prometheus --strip-components=1
  echo "Installing..."
  id -u prometheus &>/dev/null || sudo useradd -M -r -s /bin/false prometheus
  sudo mkdir -p /etc/prometheus /var/lib/prometheus
  sudo apt-get install -y apt-transport-https software-properties-common
  cd prometheus
  sudo cp {prometheus,promtool} /usr/local/bin/
  sudo chown prometheus:prometheus /usr/local/bin/{prometheus,promtool}
  sudo chown -R prometheus:prometheus /etc/prometheus
  sudo chown prometheus:prometheus /var/lib/prometheus
  sudo cp prometheus.yml /etc/prometheus/

  #creating the service file
  {
    echo "[Unit]"
    echo "Description=Prometheus"
    echo "Documentation=https://prometheus.io/docs/introduction/overview/"
    echo "Wants=network-online.target"
    echo "After=network-online.target"
    echo ""
    echo "[Service]"
    echo "Type=simple"
    echo "User=prometheus"
    echo "Group=prometheus"
    echo "ExecReload=/bin/kill -HUP \$MAINPID"
    echo "ExecStart=/usr/local/bin/prometheus   --config.file=/etc/prometheus/prometheus.yml   --storage.tsdb.path=/var/lib/prometheus   --web.listen-address=127.0.0.1:9090   --web.external-url="
    echo ""
    echo "SyslogIdentifier=prometheus"
    echo "Restart=always"
    echo ""
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  }>>prometheus.service
  sudo cp prometheus.service /etc/systemd/system/prometheus.service

  echo "Creating Prometheus service..."
  sudo systemctl daemon-reload
  sudo systemctl start prometheus
  sudo systemctl enable prometheus

  echo
  echo "Done!"
  echo
  echo "Prometheus service should be up and running now."
  echo "To check that the service is running use the following command (q to exit):"
  echo "sudo systemctl status prometheus"
  echo
  echo "You can also check Prometheus web interface, available on http://your-node-host-ip:9090/"
  echo
  echo "If everything looks ok you can now continue with installing Grafana. Refer to the tutorial:"
  echo "https://docs.avax.network/nodes/maintain/setting-up-node-monitoring#grafana"
  echo
  echo "Reach out to us on https://chat.avax.network if you're having problems."

  exit 0
}

install_grafana() {
  echo "AvalancheGo monitoring installer"
  echo "--------------------------------"
  echo "STEP 2: Installing Grafana"
  echo
  sudo mkdir -p /etc/apt/keyrings/
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
  sudo apt-get update -y
  sudo apt-get install grafana -y

  echo "Starting Grafana service..."
  sudo systemctl daemon-reload
  sudo systemctl start grafana-server
  sudo systemctl enable grafana-server.service

  echo
  echo "Done!"
  echo
  echo "Grafana service should be up and running now."
  echo "To check that the service is running use the following command (q to exit):"
  echo "sudo systemctl status grafana-server"
  echo
  echo "You can also check Grafana web interface, available on http://your-node-host-ip:3000/"
  echo
  echo "Now you need to set up Prometheus as a data source for Grafana. Refer to the tutorial:"
  echo "https://docs.avax.network/nodes/maintain/setting-up-node-monitoring#exporter"
  echo
  echo "Reach out to us on https://chat.avax.network if you're having problems."

  exit 0
}

install_exporter() {
  echo "AvalancheGo monitoring installer"
  echo "--------------------------------"
  echo "STEP 3: Installing node_exporter"
  echo
  get_environment
  mkdir -p /tmp/avalanche-monitoring-installer/exporter_archive
  cd /tmp/avalanche-monitoring-installer/exporter_archive
  echo "Dowloading archive..."
  nodeFileName="$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep -o "http.*linux-$getArch\.tar\.gz")"
  echo $nodeFileName
  wget -nv --show-progress -O node_exporter.tar.gz "$nodeFileName"
  tar xvf node_exporter.tar.gz -C /tmp/avalanche-monitoring-installer/exporter_archive --strip-components=1
  sudo mv /tmp/avalanche-monitoring-installer/exporter_archive/node_exporter /usr/local/bin
  echo "Installed, version:"
  node_exporter --version
  echo
  echo "Creating service..."

  {
    echo "[Unit]"
    echo "Description=Node exporter"
    echo "Documentation=https://github.com/prometheus/node_exporter"
    echo "Wants=network-online.target"
    echo "After=network-online.target"
    echo ""
    echo "[Service]"
    echo "Type=simple"
    echo "User=prometheus"
    echo "Group=prometheus"
    echo "ExecReload=/bin/kill -HUP \$MAINPID"
    echo "ExecStart=/usr/local/bin/node_exporter \\"
    echo "    --collector.cpu \\"
    echo "    --collector.diskstats \\"
    echo "    --collector.filesystem \\"
    echo "    --collector.loadavg \\"
    echo "    --collector.meminfo \\"
    echo "    --collector.filefd \\"
    echo "    --collector.netdev \\"
    echo "    --collector.stat \\"
    echo "    --collector.netstat \\"
    echo "    --collector.systemd \\"
    echo "    --collector.uname \\"
    echo "    --collector.vmstat \\"
    echo "    --collector.time \\"
    echo "    --collector.mdadm \\"
    echo "    --collector.zfs \\"
    echo "    --collector.tcpstat \\"
    echo "    --collector.bonding \\"
    echo "    --collector.hwmon \\"
    echo "    --collector.arp \\"
    echo "    --web.listen-address=127.0.0.1:9100 \\"
    echo "    --web.telemetry-path=\"/metrics\""
    echo ""
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >node_exporter.service
  sudo cp node_exporter.service /etc/systemd/system/node_exporter.service

  sudo systemctl daemon-reload
  sudo systemctl start node_exporter
  sudo systemctl enable node_exporter

  echo "Finishing configuration..."

  cp /etc/prometheus/prometheus.yml .
  {
    echo "  - job_name: 'avalanchego'"
    echo "    metrics_path: '/ext/metrics'"
    echo "    static_configs:"
    echo "      - targets: ['localhost:9650']"
    echo "  - job_name: 'avalanchego-machine'"
    echo "    static_configs:"
    echo "      - targets: ['localhost:9100']"
    echo "        labels:"
    echo "          alias: 'machine'"
  }>>prometheus.yml
  sudo cp prometheus.yml /etc/prometheus/
  sudo systemctl restart prometheus
  echo
  echo "Done!"
  echo
  echo "Node_exporter service should be up and running now."
  echo "To check that the service is running use the following command (q to exit):"
  echo "sudo systemctl status node_exporter"
  echo
  echo "Now you need to set up Grafana dashboards next. Refer to the tutorial:"
  echo "https://docs.avax.network/nodes/maintain/setting-up-node-monitoring#dashboards"
  echo
  echo "Reach out to us on https://chat.avax.network if you're having problems."
}

install_loki() {
  echo "AvalancheGo monitoring installer"
  echo "--------------------------------"
  echo "STEP 5: Installing Loki (log aggregation server)"
  echo
  echo "This should be run on your MONITORING SERVER (where Grafana runs)."
  echo
  get_environment
  check_reqs

  mkdir -p /tmp/avalanche-monitoring-installer/loki
  cd /tmp/avalanche-monitoring-installer/loki

  # Get latest Loki version
  lokiVersion="$(curl -s https://api.github.com/repos/grafana/loki/releases/latest | grep -Po '"tag_name": "v\K[^"]*')"
  echo "Latest Loki version: $lokiVersion"

  lokiFileName="https://github.com/grafana/loki/releases/download/v${lokiVersion}/loki-linux-${getArch}.zip"
  echo "Downloading: $lokiFileName"
  wget -nv --show-progress -O loki.zip "$lokiFileName"

  if ! command -v unzip &> /dev/null; then
    echo "Installing unzip..."
    sudo apt-get install unzip -y
  fi

  unzip -o loki.zip
  sudo mv "loki-linux-${getArch}" /usr/local/bin/loki
  sudo chmod +x /usr/local/bin/loki

  echo "Installed Loki version:"
  /usr/local/bin/loki --version

  # Create loki user
  id -u loki &>/dev/null || sudo useradd -M -r -s /bin/false loki

  # Create directories
  sudo mkdir -p /etc/loki /var/lib/loki
  sudo chown -R loki:loki /var/lib/loki

  # Create config file
  echo "Creating Loki configuration..."
  cat > loki-config.yaml << 'LOKICONFIG'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 720h

storage_config:
  filesystem:
    directory: /var/lib/loki/chunks
LOKICONFIG

  sudo cp loki-config.yaml /etc/loki/loki-config.yaml

  # Create systemd service
  echo "Creating Loki service..."
  cat > loki.service << 'LOKISERVICE'
[Unit]
Description=Loki Log Aggregation System
Documentation=https://grafana.com/docs/loki/latest/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
LOKISERVICE

  sudo cp loki.service /etc/systemd/system/loki.service

  sudo systemctl daemon-reload
  sudo systemctl start loki
  sudo systemctl enable loki

  echo
  echo "Done!"
  echo
  echo "Loki service should be up and running now."
  echo "To check that the service is running use the following command (q to exit):"
  echo "sudo systemctl status loki"
  echo
  echo "Loki API is available on http://localhost:3100"
  echo "To verify: curl http://localhost:3100/ready"
  echo
  echo "Next steps:"
  echo "1. Run --4 to install dashboards (includes Loki datasource)"
  echo "2. Run --6 on each Avalanche node to install Promtail"
  echo

  exit 0
}

install_promtail() {
  echo "AvalancheGo monitoring installer"
  echo "--------------------------------"
  echo "STEP 6: Installing Promtail (log shipper)"
  echo
  echo "This should be run on each AVALANCHE NODE to ship logs to Loki."
  echo
  get_environment
  check_reqs

  # Prompt for Loki server address
  read -p "Enter Loki server address (e.g., 192.168.1.100 or your-monitoring-server.com): " LOKI_HOST
  if [ -z "$LOKI_HOST" ]; then
    echo "Loki server address is required. Exiting."
    exit 1
  fi

  read -p "Enter Loki port [3100]: " LOKI_PORT
  LOKI_PORT=${LOKI_PORT:-3100}

  read -p "Enter a name for this node (e.g., aws-validator-01): " NODE_NAME
  if [ -z "$NODE_NAME" ]; then
    NODE_NAME="$(hostname)"
    echo "Using hostname: $NODE_NAME"
  fi

  read -p "Enter network identifier (e.g., mainnet, fuji) [mainnet]: " NETWORK_UUID
  NETWORK_UUID=${NETWORK_UUID:-mainnet}

  mkdir -p /tmp/avalanche-monitoring-installer/promtail
  cd /tmp/avalanche-monitoring-installer/promtail

  # Get latest Loki/Promtail version
  lokiVersion="$(curl -s https://api.github.com/repos/grafana/loki/releases/latest | grep -Po '"tag_name": "v\K[^"]*')"
  echo "Latest Promtail version: $lokiVersion"

  promtailFileName="https://github.com/grafana/loki/releases/download/v${lokiVersion}/promtail-linux-${getArch}.zip"
  echo "Downloading: $promtailFileName"
  wget -nv --show-progress -O promtail.zip "$promtailFileName"

  if ! command -v unzip &> /dev/null; then
    echo "Installing unzip..."
    sudo apt-get install unzip -y
  fi

  unzip -o promtail.zip
  sudo mv "promtail-linux-${getArch}" /usr/local/bin/promtail
  sudo chmod +x /usr/local/bin/promtail

  echo "Installed Promtail version:"
  /usr/local/bin/promtail --version

  # Create directories
  sudo mkdir -p /etc/promtail /var/lib/promtail

  # Detect AvalancheGo log path
  AVAGO_LOG_PATH="/var/log/avalanchego"
  if [ -d "$HOME/.avalanchego/logs" ]; then
    AVAGO_LOG_PATH="$HOME/.avalanchego/logs"
  fi
  read -p "Enter AvalancheGo log path [$AVAGO_LOG_PATH]: " USER_LOG_PATH
  AVAGO_LOG_PATH=${USER_LOG_PATH:-$AVAGO_LOG_PATH}

  # Create config file
  echo "Creating Promtail configuration..."
  cat > promtail-config.yaml << PROMTAILCONFIG
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/push

scrape_configs:
  - job_name: avalanchego
    static_configs:
      - targets:
          - localhost
        labels:
          job: avalanchego
          node: "${NODE_NAME}"
          network_uuid: "${NETWORK_UUID}"
          __path__: ${AVAGO_LOG_PATH}/*.log

    pipeline_stages:
      - multiline:
          firstline: '^\d{4}-\d{2}-\d{2}|^\[|^{'
          max_wait_time: 3s

  - job_name: systemd
    journal:
      labels:
        job: systemd
        node: "${NODE_NAME}"
        network_uuid: "${NETWORK_UUID}"
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
      - source_labels: ['__journal__systemd_unit']
        regex: 'avalanchego.*'
        action: keep
PROMTAILCONFIG

  sudo cp promtail-config.yaml /etc/promtail/promtail-config.yaml

  # Create systemd service
  echo "Creating Promtail service..."
  cat > promtail.service << 'PROMTAILSERVICE'
[Unit]
Description=Promtail Log Shipper
Documentation=https://grafana.com/docs/loki/latest/clients/promtail/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yaml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
PROMTAILSERVICE

  sudo cp promtail.service /etc/systemd/system/promtail.service

  sudo systemctl daemon-reload
  sudo systemctl start promtail
  sudo systemctl enable promtail

  echo
  echo "Done!"
  echo
  echo "Promtail service should be up and running now."
  echo "To check that the service is running use the following command (q to exit):"
  echo "sudo systemctl status promtail"
  echo
  echo "Promtail is configured to:"
  echo "  - Ship logs to: http://${LOKI_HOST}:${LOKI_PORT}"
  echo "  - Node name: ${NODE_NAME}"
  echo "  - Network: ${NETWORK_UUID}"
  echo "  - Log path: ${AVAGO_LOG_PATH}/*.log"
  echo
  echo "To verify logs are being shipped, check the Logs dashboard in Grafana."
  echo

  exit 0
}

install_dashboards() {
  #check for installation
  if test -f "/etc/grafana/grafana.ini"; then
    echo "AvalancheGo monitoring installer"
    echo "--------------------------------"
  else
    echo "Node monitoring installation not found!"
    echo
    echo "Please refer to the tutorial:"
    echo "https://docs.avax.network/nodes/maintain/setting-up-node-monitoring"
    echo
    usage
    exit 0
  fi

  if test -f "/etc/grafana/provisioning/dashboards/avalanche.yaml"; then
    echo "STEP 4: Installing Grafana dashboards"
    provisioningDone=true
    echo
    echo "Dashboards already provisioned, switching to upgrade mode."
  else
    provisioningDone=false
  fi

  echo
  echo "Downloading..."
  mkdir -p /tmp/avalanche-monitoring-installer/dashboards-install
  cd /tmp/avalanche-monitoring-installer/dashboards-install

  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/c_chain.json
  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/database.json
  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/logs.json
  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/machine.json
  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/main.json
  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/network.json
  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/p_chain.json
  wget -nd -m -nv https://raw.githubusercontent.com/Benqi-fi/avalanche-monitoring/main/grafana/dashboards/x_chain.json

  sudo mkdir -p /etc/grafana/dashboards
  sudo cp *.json /etc/grafana/dashboards

  if [ "$provisioningDone" = "false" ]; then
    echo
    echo "Provisioning dashboards..."
    {
      echo "apiVersion: 1"
      echo ""
      echo "providers:"
      echo "  - name: 'Avalanche official'"
      echo "    orgId: 1"
      echo "    folder: ''"
      echo "    folderUid: ''"
      echo "    type: file"
      echo "    disableDeletion: false"
      echo "    updateIntervalSeconds: 30"
      echo "    allowUiUpdates: true"
      echo "    options:"
      echo "      path: /etc/grafana/dashboards"
      echo "      foldersFromFilesStructure: true"
    } >>avalanche.yaml
    sudo cp avalanche.yaml /etc/grafana/provisioning/dashboards/
    echo "Provisioning datasources..."
    {
      echo "apiVersion: 1"
      echo ""
      echo "datasources:"
      echo "  - name: Prometheus"
      echo "    type: prometheus"
      echo "    access: proxy"
      echo "    orgId: 1"
      echo "    url: http://localhost:9090"
      echo "    isDefault: true"
      echo "    version: 1"
      echo "    editable: false"
      echo "  - name: Loki"
      echo "    type: loki"
      echo "    access: proxy"
      echo "    orgId: 1"
      echo "    url: http://localhost:3100"
      echo "    version: 1"
      echo "    editable: false"
    } >>prom.yaml
    sudo cp prom.yaml /etc/grafana/provisioning/datasources/
    sudo systemctl restart grafana-server
  fi
  echo
  echo "Done!"
  echo
  echo "AvalancheGo Grafana dashboards have been installed and updated."
  echo "It might take up to 30s for new versions to show up in Grafana."
  echo
  echo "Reach out to us on https://chat.avax.network if you're having problems."
}

if [ $# -ne 0 ] #arguments check
then
  case $1 in
    --1) #install prometheus
      install_prometheus
      exit 0
      ;;
    --2) #install grafana
      install_grafana
      exit 0
      ;;
    --3) #install node_exporter
      install_exporter
      exit 0
      ;;
    --4) #install AvalancheGo dashboards
      install_dashboards
      exit 0
      ;;
    --5) #install Loki
      install_loki
      exit 0
      ;;
    --6) #install Promtail
      install_promtail
      exit 0
      ;;
    --help)
      usage
      exit 0
      ;;
  esac
fi
install_dashboards

exit 0
