#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================"
echo "        UMAS K3s Deployment"
echo "============================================"
echo ""

echo ">>> Checking for kubectl..."
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH."
    exit 1
fi
echo "    kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

cd "$PROJECT_DIR"

echo ">>> Checking for .env file..."
if [ ! -f .env ]; then
    echo "ERROR: .env file not found. Please create it from .env.example."
    exit 1
fi

echo ">>> Creating namespace 'umas'..."
kubectl create namespace umas --dry-run=client -o yaml | kubectl apply -f -

echo ">>> Creating secret from .env..."
kubectl create secret generic umas-secrets \
    --from-env-file=.env \
    -n umas \
    --dry-run=client -o yaml | kubectl apply -f -

echo ">>> Applying namespace manifest..."
kubectl apply -f k8s/namespace.yml

echo ">>> Applying PVC manifests..."
if [ -d k8s/pvcs ]; then
    kubectl apply -f k8s/pvcs/ -n umas
fi

echo ">>> Applying ConfigMap manifests..."
if [ -d k8s/configmaps ]; then
    kubectl apply -f k8s/configmaps/ -n umas
fi

echo ">>> Applying Deployment manifests..."
if [ -d k8s/deployments ]; then
    kubectl apply -f k8s/deployments/ -n umas
fi

echo ">>> Applying Service manifests..."
if [ -d k8s/services ]; then
    kubectl apply -f k8s/services/ -n umas
fi

echo ">>> Applying DaemonSet manifests..."
if [ -d k8s/daemonsets ]; then
    kubectl apply -f k8s/daemonsets/ -n umas
fi

echo ">>> Applying Ingress manifests..."
if [ -d k8s/ingress ]; then
    kubectl apply -f k8s/ingress/ -n umas
fi

echo ">>> Waiting for all pods to be ready (timeout: 300s)..."
kubectl wait --for=condition=ready pod --all -n umas --timeout=300s

echo ""
echo "============================================"
echo "          Deployment Complete"
echo "============================================"
echo ""
echo ">>> Pod Status:"
kubectl get pods -n umas
echo ""
echo ">>> Service URLs:"
kubectl get svc -n umas
echo ""
echo "Access URLs (via NodePort or Ingress):"
echo "  Grafana:      http://<NODE_IP>:3000"
echo "  Prometheus:   http://<NODE_IP>:9090"
echo "  Alertmanager: http://<NODE_IP>:9093"
echo "  Zabbix:       http://<NODE_IP>:8081"
echo ""
echo "============================================"
