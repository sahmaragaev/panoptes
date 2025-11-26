#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

echo "============================================"
echo "          PANOPTES VPS Setup"
echo "============================================"
echo ""

echo ">>> Updating system packages..."
apt update && apt upgrade -y

echo ">>> Installing Docker CE prerequisites..."
apt install -y ca-certificates curl gnupg lsb-release

echo ">>> Adding Docker official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo ">>> Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update

echo ">>> Installing Docker CE and Docker Compose plugin..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Installing K3s..."
curl -sfL https://get.k3s.io | sh -

echo ">>> Configuring UFW firewall rules..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 6443
ufw allow 10250
ufw --force enable

echo ">>> Installing stress-ng for demo simulations..."
apt install -y stress-ng

echo ">>> Installing promtool..."
PROMETHEUS_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
PROMTOOL_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
PROMTOOL_TMP=$(mktemp -d)
curl -fsSL "$PROMTOOL_URL" -o "${PROMTOOL_TMP}/prometheus.tar.gz"
tar xzf "${PROMTOOL_TMP}/prometheus.tar.gz" -C "${PROMTOOL_TMP}" --strip-components=1
cp "${PROMTOOL_TMP}/promtool" /usr/local/bin/promtool
chmod +x /usr/local/bin/promtool
rm -rf "${PROMTOOL_TMP}"

echo ">>> Configuring Docker daemon..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DAEMON_EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["8.8.8.8", "8.8.4.4"]
}
DAEMON_EOF

echo ">>> Enabling and starting Docker..."
systemctl enable docker
systemctl start docker

echo ">>> Creating /opt/monitoring directory..."
mkdir -p /opt/monitoring

echo ""
echo "============================================"
echo "          Setup Complete - Status Summary"
echo "============================================"
echo ""
echo "Docker version:"
docker --version
echo ""
echo "K3s version:"
k3s --version
echo ""
echo "UFW status:"
ufw status
echo ""
echo "============================================"
echo "          PANOPTES VPS Setup finished"
echo "============================================"
