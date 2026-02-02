<#
.SYNOPSIS
    Scale OpenFrame Azure deployment.

.DESCRIPTION
    This script scales AKS nodes and other resources for the OpenFrame platform.

.PARAMETER ResourceGroup
    Name of the Azure Resource Group

.PARAMETER Nodes
    Target number of AKS nodes

.PARAMETER MinNodes
    Minimum nodes for autoscaler

.PARAMETER MaxNodes
    Maximum nodes for autoscaler

.PARAMETER NodeSize
    VM size for nodes (for node pool updates)

.EXAMPLE
    ./scale.ps1 -ResourceGroup openframe-prod -Nodes 5
    ./scale.ps1 -ResourceGroup openframe-prod -MinNodes 3 -MaxNodes 10
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [int]$Nodes,

    [Parameter(Mandatory = $false)]
    [int]$MinNodes,

    [Parameter(Mandatory = $false)]
    [int]$MaxNodes,

    [Parameter(Mandatory = $false)]
    [string]$NodeSize
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

Write-Step "OpenFrame Azure Scaling"

# Get AKS cluster name
$aksName = az aks list --resource-group $ResourceGroup --query "[0].name" -o tsv
if (-not $aksName) {
    Write-Host "No AKS cluster found in resource group: $ResourceGroup" -ForegroundColor Red
    exit 1
}

Write-Host "AKS Cluster: $aksName" -ForegroundColor Green

# Get current node pool info
$nodePools = az aks nodepool list --resource-group $ResourceGroup --cluster-name $aksName | ConvertFrom-Json
$primaryPool = $nodePools | Where-Object { $_.mode -eq "System" } | Select-Object -First 1

Write-Host "`nCurrent Configuration:" -ForegroundColor Yellow
Write-Host "  Node Pool: $($primaryPool.name)" -ForegroundColor White
Write-Host "  Current Count: $($primaryPool.count)" -ForegroundColor White
Write-Host "  Min Count: $($primaryPool.minCount)" -ForegroundColor White
Write-Host "  Max Count: $($primaryPool.maxCount)" -ForegroundColor White
Write-Host "  VM Size: $($primaryPool.vmSize)" -ForegroundColor White

if ($Nodes) {
    Write-Step "Scaling to $Nodes nodes"
    az aks scale `
        --resource-group $ResourceGroup `
        --name $aksName `
        --node-count $Nodes `
        --nodepool-name $primaryPool.name

    Write-Host "  Scaled to $Nodes nodes" -ForegroundColor Green
}

if ($MinNodes -or $MaxNodes) {
    Write-Step "Updating Autoscaler"

    $updateParams = @(
        "--resource-group", $ResourceGroup,
        "--cluster-name", $aksName,
        "--name", $primaryPool.name,
        "--enable-cluster-autoscaler"
    )

    if ($MinNodes) {
        $updateParams += "--min-count", $MinNodes
    }
    if ($MaxNodes) {
        $updateParams += "--max-count", $MaxNodes
    }

    az aks nodepool update @updateParams

    Write-Host "  Updated autoscaler settings" -ForegroundColor Green
}

if ($NodeSize) {
    Write-Host "`nNote: Changing VM size requires creating a new node pool." -ForegroundColor Yellow
    Write-Host "Use 'az aks nodepool add' to create a new pool with the desired size." -ForegroundColor Yellow
}

# Show final state
Write-Step "Final Configuration"
$nodePools = az aks nodepool list --resource-group $ResourceGroup --cluster-name $aksName | ConvertFrom-Json
foreach ($pool in $nodePools) {
    Write-Host "  Pool: $($pool.name)" -ForegroundColor White
    Write-Host "    Count: $($pool.count)" -ForegroundColor White
    Write-Host "    Min: $($pool.minCount), Max: $($pool.maxCount)" -ForegroundColor White
    Write-Host "    VM Size: $($pool.vmSize)" -ForegroundColor White
}
