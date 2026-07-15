#!/usr/bin/env bash
# teardown.sh — Delete the kind cluster and all local images
set -euo pipefail

CLUSTER_NAME="ad-analytics"

echo "Deleting kind cluster: ${CLUSTER_NAME}"
kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null && echo "Cluster deleted" || echo "Cluster not found"

echo "Removing local Docker images…"
for img in kafka flink-job click-api ad-ui report-ui; do
  docker rmi "ad-analytics/${img}:latest" 2>/dev/null && echo "Removed: ad-analytics/${img}" || true
done

echo "Done."
