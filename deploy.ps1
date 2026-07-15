#Requires -Version 5.1
<#
.SYNOPSIS
    One-shot deploy script for the Ad Analytics stack on kind (Windows PowerShell).

.DESCRIPTION
    1. Creates a kind cluster with ingress-ready config
    2. Installs NGINX ingress controller
    3. Builds Docker images (Maven for Flink job, npm for Node.js apps)
    4. Loads images into kind
    5. Deploys all services: Zookeeper, Kafka, MongoDB, Flink, Click API,
       Ad UI, Report UI, Prometheus, Grafana
    6. Waits for everything to be healthy and prints access URLs

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -ClusterName my-cluster -WindowSeconds 30
    .\deploy.ps1 -SkipBuild -SkipCluster
#>

param(
    [string]$ClusterName   = "ad-analytics",
    [int]   $WindowSeconds = 60,
    [switch]$SkipBuild,
    [switch]$SkipCluster
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---- Helpers -----------------------------------------------------------------
function Write-Step { param($msg) Write-Host "`n--- $msg " -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[..]  $msg" -ForegroundColor Blue }
function Write-Warn { param($msg) Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Write-Fail {
    param($msg)
    Write-Host "[ERR] $msg" -ForegroundColor Red
    exit 1
}

# Run a native command and tolerate a non-zero exit code.
# Returns the combined stdout+stderr as a string array.
function Invoke-Native {
    param([scriptblock]$Cmd)
    $ErrorActionPreference = "Continue"
    [string[]]$out = @(& $Cmd 2>&1 | Where-Object { $_ -is [string] })
    $ErrorActionPreference = "Stop"
    return $out
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- 1. Prerequisites --------------------------------------------------------
Write-Step "Checking prerequisites"

foreach ($tool in @("docker", "kind", "kubectl", "mvn", "node")) {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    if ($found) {
        Write-Ok "$tool  ->  $($found.Source)"
    } else {
        Write-Fail "$tool is required but not found in PATH. Install it and re-run."
    }
}

try {
    docker info 2>&1 | Out-Null
    Write-Ok "Docker daemon is running"
} catch {
    Write-Fail "Docker daemon is not running. Start Docker Desktop and re-run."
}

# ---- 2. Create kind cluster --------------------------------------------------
Write-Step "Setting up kind cluster: $ClusterName"

if ($SkipCluster) {
    Write-Warn "-SkipCluster set -- skipping cluster creation"
} else {
    # kind get clusters exits non-zero with a message on stderr when no clusters exist
    $existingClusters = Invoke-Native { kind get clusters }
    $clusterExists = $existingClusters -contains $ClusterName

    if ($clusterExists) {
        Write-Warn "Kind cluster '$ClusterName' already exists -- skipping creation"
    } else {
        Write-Info "Writing kind config and creating cluster..."

        $kindConfigFile = Join-Path $env:TEMP "kind-config-$ClusterName.yaml"

        @(
            'kind: Cluster',
            'apiVersion: kind.x-k8s.io/v1alpha4',
            'nodes:',
            '  - role: control-plane',
            '    kubeadmConfigPatches:',
            '      - |',
            '        kind: InitConfiguration',
            '        nodeRegistration:',
            '          kubeletExtraArgs:',
            '            node-labels: "ingress-ready=true"',
            '    extraPortMappings:',
            '      - containerPort: 80',
            '        hostPort: 80',
            '        protocol: TCP',
            '      - containerPort: 443',
            '        hostPort: 443',
            '        protocol: TCP',
            '  - role: worker',
            '  - role: worker'
        ) | Set-Content -Path $kindConfigFile -Encoding UTF8

        kind create cluster --name $ClusterName --config $kindConfigFile
        if ($LASTEXITCODE -ne 0) { Write-Fail "kind create cluster failed" }

        Remove-Item $kindConfigFile -ErrorAction SilentlyContinue
        Write-Ok "Kind cluster created"
    }
}

kubectl config use-context "kind-$ClusterName"
if ($LASTEXITCODE -ne 0) { Write-Fail "kubectl config use-context failed -- is the cluster running?" }

# ---- 3. NGINX Ingress Controller ---------------------------------------------
Write-Step "Installing NGINX Ingress Controller"

$nsCheck = Invoke-Native { kubectl get namespace ingress-nginx --ignore-not-found }
if ($nsCheck -and $nsCheck[0] -match "ingress-nginx") {
    Write-Warn "ingress-nginx already installed -- skipping"
} else {
    kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml"
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to apply ingress-nginx manifest" }

    Write-Info "Waiting for ingress controller pod (up to 3 min)..."
    kubectl wait --namespace ingress-nginx `
        --for=condition=ready pod `
        --selector=app.kubernetes.io/component=controller `
        --timeout=180s
    if ($LASTEXITCODE -ne 0) { Write-Fail "Ingress controller did not become ready in time" }
    Write-Ok "NGINX Ingress Controller ready"
}

# ---- 4. Build Docker images --------------------------------------------------
Write-Step "Building Docker images"

if ($SkipBuild) {
    Write-Warn "-SkipBuild set -- skipping image builds"
} else {
    # Kafka wrapper image (strips attestation layers so kind can load it)
    Write-Info "Pulling apache/kafka:3.7.0 and repackaging for kind..."
    @('FROM apache/kafka:3.7.0') | Set-Content "$env:TEMP\Dockerfile.kafka" -Encoding UTF8
    docker build --platform linux/amd64 -t "ad-analytics/kafka:latest" -f "$env:TEMP\Dockerfile.kafka" (Join-Path $ScriptDir "k8s")
    if ($LASTEXITCODE -ne 0) { Write-Fail "Docker build failed for kafka wrapper" }
    Write-Ok "ad-analytics/kafka built"

    # Flink Job
    Write-Info "Building Flink job JAR with Maven (first run ~3 min)..."
    Push-Location (Join-Path $ScriptDir "flink-job")
    mvn clean package -DskipTests -q
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "Maven build failed" }
    Pop-Location
    Write-Ok "Flink job JAR built"

    Write-Info "Building Docker image: ad-analytics/flink-job:latest"
    docker build -t "ad-analytics/flink-job:latest" (Join-Path $ScriptDir "flink-job")
    if ($LASTEXITCODE -ne 0) { Write-Fail "Docker build failed for flink-job" }
    Write-Ok "ad-analytics/flink-job built"

    # Node.js services
    foreach ($svc in @("click-api", "ad-ui", "report-ui")) {
        $svcPath = Join-Path $ScriptDir $svc

        Write-Info "npm install for $svc..."
        Push-Location $svcPath
        npm install --omit=dev --silent
        if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "npm install failed for $svc" }
        Pop-Location

        Write-Info "Building Docker image: ad-analytics/${svc}:latest"
        docker build -t "ad-analytics/${svc}:latest" $svcPath
        if ($LASTEXITCODE -ne 0) { Write-Fail "Docker build failed for $svc" }
        Write-Ok "ad-analytics/$svc built"
    }
}

# ---- 5. Load images into kind ------------------------------------------------
Write-Step "Loading images into kind cluster"

foreach ($img in @("kafka", "flink-job", "click-api", "ad-ui", "report-ui")) {
    Write-Info "Loading ad-analytics/${img}:latest..."
    kind load docker-image "ad-analytics/${img}:latest" --name $ClusterName
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to load image: ad-analytics/$img" }
    Write-Ok "Loaded: ad-analytics/${img}:latest"
}

# ---- 6. Apply Kubernetes manifests -------------------------------------------
Write-Step "Applying Kubernetes manifests"

$k8sDir = Join-Path $ScriptDir "k8s"
$monDir = Join-Path $k8sDir "monitoring"

kubectl apply -f (Join-Path $k8sDir "namespace.yaml")
if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to apply namespace.yaml" }

foreach ($f in @("zookeeper.yaml", "kafka.yaml", "mongodb.yaml")) {
    kubectl apply -f (Join-Path $k8sDir $f)
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to apply $f" }
}

foreach ($dep in @("kafka", "mongodb")) {
    $timeout = if ($dep -eq "kafka") { "240s" } else { "120s" }
    Write-Info "Waiting for $dep (timeout $timeout)..."
    kubectl rollout status "deployment/$dep" -n ad-analytics --timeout=$timeout
    if ($LASTEXITCODE -ne 0) { Write-Warn "$dep rollout timed out -- continuing anyway" }
    else { Write-Ok "$dep ready" }
}

foreach ($f in @("click-api.yaml", "ad-ui.yaml", "report-ui.yaml", "flink.yaml", "ingress.yaml")) {
    kubectl apply -f (Join-Path $k8sDir $f)
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to apply $f" }
}

foreach ($f in @("prometheus-configmap.yaml", "prometheus.yaml", "grafana.yaml", "ingress-monitoring.yaml")) {
    kubectl apply -f (Join-Path $monDir $f)
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to apply monitoring/$f" }
}

Write-Ok "All manifests applied"

# ---- 7. Wait for application pods --------------------------------------------
Write-Step "Waiting for application pods to be ready"

foreach ($dep in @("click-api", "ad-ui", "report-ui", "flink-jobmanager", "flink-taskmanager", "prometheus", "grafana")) {
    Write-Info "Waiting for $dep (up to 5 min)..."
    kubectl rollout status "deployment/$dep" -n ad-analytics --timeout=300s
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$dep is ready"
    } else {
        Write-Warn "$dep did not become ready within timeout"
        Write-Warn "  Check:  kubectl get pods -n ad-analytics"
        Write-Warn "  Logs:   kubectl logs -n ad-analytics deployment/$dep"
    }
}

# ---- 8. Summary --------------------------------------------------------------
Write-Step "Deployment complete!"

Write-Host ""
Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Green
Write-Host "|         Ad Analytics Stack is UP                                 |" -ForegroundColor Green
Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Green
Write-Host "|  Ad Demo UI    ->  http://localhost/ads                          |" -ForegroundColor Green
Write-Host "|  Report UI     ->  http://localhost/reports                      |" -ForegroundColor Green
Write-Host "|  Click API     ->  http://localhost/api/clicks  (POST)           |" -ForegroundColor Green
Write-Host "|  Flink Web UI  ->  http://localhost/flink                        |" -ForegroundColor Green
Write-Host "|  Grafana       ->  http://localhost/grafana  (admin / admin123)  |" -ForegroundColor Green
Write-Host "|  Prometheus    ->  http://localhost/prometheus                   |" -ForegroundColor Green
Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Green
Write-Host "|  kubectl get pods    -n ad-analytics                             |" -ForegroundColor Green
Write-Host "|  kubectl get ingress -n ad-analytics                             |" -ForegroundColor Green
Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Info "Flink aggregates clicks in $WindowSeconds-second tumbling windows."
Write-Info "Click ads in the Ad UI, wait ~$WindowSeconds seconds, then refresh the Report UI."
