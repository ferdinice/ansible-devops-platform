#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/prometheus-userdata.log | logger -t user-data -s 2>/dev/console) 2>&1

PROMETHEUS_VERSION="3.7.1"

apt-get update -y
apt-get install -y wget tar

useradd \
  --system \
  --no-create-home \
  --shell /usr/sbin/nologin \
  prometheus || true

mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus

cd /tmp

wget -q \
  "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

tar -xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64"

install -m 0755 prometheus /usr/local/bin/prometheus
install -m 0755 promtool /usr/local/bin/promtool

cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets:
          - "localhost:9090"
EOF

chown -R prometheus:prometheus /etc/prometheus
chown -R prometheus:prometheus /var/lib/prometheus

cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.listen-address=0.0.0.0:9090 \
  --web.enable-lifecycle

Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

rm -rf \
  "/tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64" \
  "/tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"