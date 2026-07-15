#Requires -Version 5.1
<#
.SYNOPSIS
    Tears down the Ad Analytics kind cluster and removes local Docker images.

.EXAMPLE
    .\teardown.ps1
    .\teardown.ps1 -ClusterName my-cluster
    .\teardown.ps1 -KeepImages
#>

param(
    [string]$ClusterName = "ad-analytics",
    [switch]$KeepImages
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Ok   { param($msg) Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[..]  $msg" -ForegroundColor Blue }
function Write-Warn { param($msg) Write-Host "[!!]  $msg" -ForegroundColor Yellow }

Write-Info "Tearing down Ad Analytics stack (cluster: $ClusterName)..."
Write-Host ""

# ---- Delete kind cluster -----------------------------------------------------
$ErrorActionPreference = "Continue"
[string[]]$existing = @(& kind get clusters 2>&1 | Where-Object { $_ -is [string] })
$ErrorActionPreference = "SilentlyContinue"
$clusterExists = $existing -contains $ClusterName

if ($clusterExists) {
    Write-Info "Deleting kind cluster '$ClusterName'..."
    kind delete cluster --name $ClusterName
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Cluster '$ClusterName' deleted"
    } else {
        Write-Warn "Failed to delete cluster (may already be gone)"
    }
} else {
    Write-Warn "Kind cluster '$ClusterName' not found -- nothing to delete"
}

# ---- Remove local Docker images ----------------------------------------------
if ($KeepImages) {
    Write-Warn "-KeepImages set -- skipping Docker image removal"
} else {
    Write-Info "Removing local Docker images..."
    foreach ($img in @("flink-job", "click-api", "ad-ui", "report-ui")) {
        $tag = "ad-analytics/${img}:latest"
        $check = docker image inspect $tag 2>$null
        if ($check) {
            docker rmi $tag --force 2>$null
            Write-Ok "Removed: $tag"
        } else {
            Write-Warn "Image not found (skipping): $tag"
        }
    }
}

Write-Host ""
Write-Ok "Teardown complete."
