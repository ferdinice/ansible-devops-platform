#!/bin/bash
set -euo pipefail

GRAFANA_VERSION="12.2.0"
PROMETHEUS_IP="${prometheus_ip}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y wget ca-certificates

cd /tmp

wget -q \
  "https://dl.grafana.com/oss/release/grafana_$${GRAFANA_VERSION}_amd64.deb" \
  -O grafana.deb

apt-get install -y ./grafana.deb

mkdir -p /etc/grafana/provisioning/datasources

cat > /etc/grafana/provisioning/datasources/prometheus.yml <<DATASOURCE
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://$${PROMETHEUS_IP}:9090
    isDefault: true
    editable: false
DATASOURCE

# Provision dashboards from code
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /var/lib/grafana/dashboards

cat > /etc/grafana/provisioning/dashboards/platform.yml <<'DASHBOARD_PROVIDER'
apiVersion: 1

providers:
  - name: DevOps Platform
    orgId: 1
    folder: Infrastructure
    type: file
    disableDeletion: true
    editable: true
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
DASHBOARD_PROVIDER

cat > /var/lib/grafana/dashboards/platform-overview.json <<'DASHBOARD_JSON'
${dashboard_json}
DASHBOARD_JSON

chown -R grafana:grafana /var/lib/grafana/dashboards
chown -R root:grafana /etc/grafana/provisioning

systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

rm -f /tmp/grafana.deb
