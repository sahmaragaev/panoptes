#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

PANOPTES_SERVER_URL="${1:-}"
PANOPTES_API_KEY="${2:-}"
PANOPTES_TENANT="${3:-}"

if [ -z "$PANOPTES_SERVER_URL" ]; then
    read -rp "Enter Panoptes server URL (e.g. https://panoptes.example.com): " PANOPTES_SERVER_URL
fi

if [ -z "$PANOPTES_API_KEY" ]; then
    read -rp "Enter Panoptes API key: " PANOPTES_API_KEY
fi

if [ -z "$PANOPTES_TENANT" ]; then
    read -rp "Enter tenant name: " PANOPTES_TENANT
fi

echo "Downloading Grafana Alloy..."
ALLOY_VERSION=$(curl -s https://api.github.com/repos/grafana/alloy/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -sL "https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/alloy-linux-amd64.zip" -o /tmp/alloy.zip
unzip -o /tmp/alloy.zip -d /tmp/alloy
install -m 0755 /tmp/alloy/alloy-linux-amd64 /usr/local/bin/alloy
rm -rf /tmp/alloy /tmp/alloy.zip
echo "Alloy ${ALLOY_VERSION} installed to /usr/local/bin/alloy."

echo "Installing Alloy configuration..."
mkdir -p /etc/alloy
curl -sSL https://raw.githubusercontent.com/sahmaragaev/panoptes/main/agent/config.alloy -o /etc/alloy/config.alloy

echo "Creating environment file..."
cat > /etc/alloy/env <<ENVFILE
PANOPTES_SERVER_URL=${PANOPTES_SERVER_URL}
PANOPTES_API_KEY=${PANOPTES_API_KEY}
PANOPTES_TENANT=${PANOPTES_TENANT}
HOSTNAME=$(hostname)
ENVFILE
chmod 600 /etc/alloy/env

if ! command -v node_exporter &>/dev/null; then
    echo "Installing node_exporter..."
    NODE_EXPORTER_VERSION="1.9.0"
    curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" -o /tmp/node_exporter.tar.gz
    tar xzf /tmp/node_exporter.tar.gz -C /tmp
    install -m 0755 "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
    rm -rf /tmp/node_exporter*

    cat > /etc/systemd/system/node_exporter.service <<SERVICE
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable --now node_exporter
    echo "node_exporter installed and started."
else
    echo "node_exporter is already installed."
fi

echo "Creating Alloy systemd service..."
cat > /etc/systemd/system/alloy.service <<SERVICE
[Unit]
Description=Grafana Alloy
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/alloy/env
ExecStart=/usr/local/bin/alloy run /etc/alloy/config.alloy
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now alloy
echo "Alloy service enabled and started."

echo ""
echo "Installation complete. Service status:"
systemctl status alloy --no-pager
