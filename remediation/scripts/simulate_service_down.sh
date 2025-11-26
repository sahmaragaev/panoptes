#!/bin/bash
SERVICE=${1:-node-exporter}
echo "Stopping $SERVICE to trigger InstanceDown..."
docker stop $SERVICE
echo "Restore: docker start $SERVICE"
