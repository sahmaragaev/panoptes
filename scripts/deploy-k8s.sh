#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================"
echo "        PANOPTES K3s Deployment"
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

echo ">>> Creating namespace 'panoptes'..."
kubectl create namespace panoptes --dry-run=client -o yaml | kubectl apply -f -

echo ">>> Creating secret from .env..."
kubectl create secret generic panoptes-secrets \
    --from-env-file=.env \
    -n panoptes \
    --dry-run=client -o yaml | kubectl apply -f -

echo ">>> Applying namespace manifest..."
kubectl apply -f k8s/namespace.yml

echo ">>> Applying PVC manifests..."
if [ -d k8s/pvcs ]; then
    kubectl apply -f k8s/pvcs/ -n panoptes
fi

echo ">>> Applying ConfigMap manifests..."
if [ -d k8s/configmaps ]; then
    kubectl apply -f k8s/configmaps/ -n panoptes
fi

echo ">>> Applying Deployment manifests..."
if [ -d k8s/deployments ]; then
    kubectl apply -f k8s/deployments/ -n panoptes
fi

echo ">>> Applying Service manifests..."
if [ -d k8s/services ]; then
    kubectl apply -f k8s/services/ -n panoptes
fi

echo ">>> Applying DaemonSet manifests..."
if [ -d k8s/daemonsets ]; then
    kubectl apply -f k8s/daemonsets/ -n panoptes
fi

echo ">>> Applying Ingress manifests..."
if [ -d k8s/ingress ]; then
    kubectl apply -f k8s/ingress/ -n panoptes
fi

echo ">>> Waiting for all pods to be ready (timeout: 300s)..."
kubectl wait --for=condition=ready pod --all -n panoptes --timeout=300s

echo ""
echo "============================================"
echo "          Deployment Complete"
echo "============================================"
echo ""
echo ">>> Pod Status:"
kubectl get pods -n panoptes
echo ""
echo ">>> Service URLs:"
kubectl get svc -n panoptes
echo ""
echo "Access URLs (via NodePort or Ingress):"
echo "  Grafana:      http://<NODE_IP>:3000"
echo "  Prometheus:   http://<NODE_IP>:9090"
echo "  Alertmanager: http://<NODE_IP>:9093"
echo ""
echo "============================================"
