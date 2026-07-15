#!/usr/bin/env bash
# =============================================================================
# deploy.sh — One-shot script to:
#   1. Create a kind cluster with ingress-ready config
#   2. Install NGINX ingress controller
#   3. Build Docker images and load them into kind
#   4. Deploy all services: Kafka (KRaft), MongoDB, Flink, Click API,
#      Ad UI, Report UI, Prometheus, Grafana
#   5. Wait for everything to be healthy
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[OK]${RESET} $*"; }
info() { echo -e "${BLUE}[..]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!!]${RESET} $*"; }
step() { echo -e "\n${CYAN}--- $* ${RESET}"; }
die()  { echo -e "${RED}[ERR] $*${RESET}" >&2; exit 1; }

CLUSTER_NAME="ad-analytics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
step "Checking prerequisites"
for tool in docker kind kubectl mvn node; do
  if command -v "$tool" &>/dev/null; then
    log "$tool found: $(command -v $tool)"
  else
    die "$tool is required but not installed. Please install it and re-run."
  fi
done

# ── 2. Create kind cluster ────────────────────────────────────────────────────
step "Creating kind cluster: $CLUSTER_NAME"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  warn "Kind cluster '${CLUSTER_NAME}' already exists — skipping creation"
else
  info "Creating cluster with ingress-ready configuration..."
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
  - role: worker
EOF
  log "Kind cluster created"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

# ── 3. Install NGINX Ingress Controller ───────────────────────────────────────
step "Installing NGINX Ingress Controller"

if kubectl get namespace ingress-nginx &>/dev/null; then
  warn "ingress-nginx namespace already exists — skipping install"
else
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  info "Waiting for ingress controller to be ready (up to 3 min)..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s
  log "NGINX Ingress Controller ready"
fi

# ── 4. Build Docker images ────────────────────────────────────────────────────
step "Building Docker images"

# Kafka wrapper — apache/kafka:3.7.0 has attestation layers that kind cannot
# import directly. Build a plain single-arch wrapper image to strip them.
info "Pulling apache/kafka:3.7.0 and repackaging for kind..."
echo 'FROM apache/kafka:3.7.0' > /tmp/Dockerfile.kafka
docker build --platform linux/amd64 -t ad-analytics/kafka:latest \
  -f /tmp/Dockerfile.kafka "${SCRIPT_DIR}/k8s"
log "ad-analytics/kafka built"

# Flink Job (Java — Maven build first)
info "Building Flink job JAR (first run ~3 min)..."
(cd "${SCRIPT_DIR}/flink-job" && mvn clean package -DskipTests -q)
log "Flink job JAR built"

info "Building Docker image: ad-analytics/flink-job:latest"
docker build -t ad-analytics/flink-job:latest "${SCRIPT_DIR}/flink-job"
log "ad-analytics/flink-job built"

# Node.js apps
for svc in click-api ad-ui report-ui; do
  info "npm install for ${svc}..."
  (cd "${SCRIPT_DIR}/${svc}" && npm install --omit=dev --silent)
  info "Building Docker image: ad-analytics/${svc}:latest"
  docker build -t "ad-analytics/${svc}:latest" "${SCRIPT_DIR}/${svc}"
  log "ad-analytics/${svc} built"
done

# ── 5. Load images into kind ──────────────────────────────────────────────────
step "Loading images into kind cluster"

for img in kafka flink-job click-api ad-ui report-ui; do
  info "Loading ad-analytics/${img}:latest..."
  kind load docker-image "ad-analytics/${img}:latest" --name "${CLUSTER_NAME}"
  log "Loaded: ad-analytics/${img}:latest"
done

# ── 6. Apply Kubernetes manifests ─────────────────────────────────────────────
step "Applying Kubernetes manifests"

kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"

# Infrastructure — Kafka runs in KRaft mode (no Zookeeper needed)
kubectl apply -f "${SCRIPT_DIR}/k8s/kafka.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/mongodb.yaml"

info "Waiting for Kafka (up to 240s)..."
kubectl rollout status deployment/kafka -n ad-analytics --timeout=240s \
  && log "Kafka ready" \
  || warn "Kafka rollout timed out — continuing anyway"

info "Waiting for MongoDB (up to 120s)..."
kubectl rollout status deployment/mongodb -n ad-analytics --timeout=120s \
  && log "MongoDB ready" \
  || warn "MongoDB rollout timed out — continuing anyway"

# Application services
kubectl apply -f "${SCRIPT_DIR}/k8s/click-api.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/ad-ui.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/report-ui.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/flink.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/ingress.yaml"

# Monitoring
kubectl apply -f "${SCRIPT_DIR}/k8s/monitoring/prometheus-configmap.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/monitoring/prometheus.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/monitoring/grafana.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/monitoring/ingress-monitoring.yaml"

log "All manifests applied"

# ── 7. Wait for application pods ──────────────────────────────────────────────
step "Waiting for application pods to be ready"

for dep in click-api ad-ui report-ui flink-jobmanager flink-taskmanager prometheus grafana; do
  info "Waiting for ${dep} (up to 5 min)..."
  kubectl rollout status "deployment/${dep}" -n ad-analytics --timeout=300s \
    && log "${dep} ready" \
    || warn "${dep} did not become ready within timeout — check: kubectl get pods -n ad-analytics"
done

# ── 8. Summary ────────────────────────────────────────────────────────────────
step "Deployment complete!"

echo ""
echo -e "${GREEN}+-------------------------------------------------------------------+${RESET}"
echo -e "${GREEN}|         Ad Analytics Stack is UP                                 |${RESET}"
echo -e "${GREEN}+-------------------------------------------------------------------+${RESET}"
echo -e "${GREEN}|  Ad Demo UI    ->  http://localhost/ads                          |${RESET}"
echo -e "${GREEN}|  Report UI     ->  http://localhost/reports                      |${RESET}"
echo -e "${GREEN}|  Click API     ->  http://localhost/api/clicks  (POST)           |${RESET}"
echo -e "${GREEN}|  Flink Web UI  ->  http://localhost/flink                        |${RESET}"
echo -e "${GREEN}|  Grafana       ->  http://localhost/grafana  (admin / admin123)  |${RESET}"
echo -e "${GREEN}|  Prometheus    ->  http://localhost/prometheus                   |${RESET}"
echo -e "${GREEN}+-------------------------------------------------------------------+${RESET}"
echo -e "${GREEN}|  kubectl get pods    -n ad-analytics                             |${RESET}"
echo -e "${GREEN}|  kubectl get ingress -n ad-analytics                             |${RESET}"
echo -e "${GREEN}+-------------------------------------------------------------------+${RESET}"
echo ""
info "Flink aggregates clicks in 60-second tumbling windows."
info "Click ads in the Ad UI, wait ~60s, then refresh the Report UI."
