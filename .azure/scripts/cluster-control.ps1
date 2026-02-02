<#
.SYNOPSIS
    Start or stop OpenFrame AKS cluster to manage costs.

.DESCRIPTION
    Stops the AKS cluster to pause compute billing, or starts it back up.
    When stopped, you only pay for storage and always-on services.

.PARAMETER ResourceGroup
    Name of the Azure Resource Group

.PARAMETER Action
    Action to perform: start, stop, or status

.EXAMPLE
    ./cluster-control.ps1 -ResourceGroup openframe-test -Action stop
    ./cluster-control.ps1 -ResourceGroup openframe-test -Action start
    ./cluster-control.ps1 -ResourceGroup openframe-test -Action status
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

# Find AKS cluster in resource group
$aksName = az aks list --resource-group $ResourceGroup --query "[0].name" -o tsv
if (-not $aksName) {
    Write-Host "No AKS cluster found in resource group: $ResourceGroup" -ForegroundColor Red
    exit 1
}

Write-Host "`nOpenFrame Cluster Control" -ForegroundColor Cyan
Write-Host "Cluster: $aksName" -ForegroundColor White
Write-Host "Resource Group: $ResourceGroup`n" -ForegroundColor White

switch ($Action) {
    "status" {
        $cluster = az aks show --resource-group $ResourceGroup --name $aksName | ConvertFrom-Json
        $powerState = $cluster.powerState.code

        Write-Host "Status: " -NoNewline
        if ($powerState -eq "Running") {
            Write-Host "RUNNING" -ForegroundColor Green
            Write-Host "`nCluster is active and billing for compute." -ForegroundColor Yellow
        } elseif ($powerState -eq "Stopped") {
            Write-Host "STOPPED" -ForegroundColor Red
            Write-Host "`nCompute billing is paused. Storage costs still apply." -ForegroundColor Green
        } else {
            Write-Host $powerState -ForegroundColor Yellow
        }

        Write-Host "`nNode Pools:" -ForegroundColor Cyan
        $nodePools = az aks nodepool list --resource-group $ResourceGroup --cluster-name $aksName | ConvertFrom-Json
        foreach ($pool in $nodePools) {
            Write-Host "  $($pool.name): $($pool.count) nodes ($($pool.vmSize))" -ForegroundColor White
        }
    }

    "stop" {
        Write-Host "Stopping cluster..." -ForegroundColor Yellow
        Write-Host "This will deallocate all nodes and pause compute billing.`n" -ForegroundColor White

        az aks stop --resource-group $ResourceGroup --name $aksName

        Write-Host "`nCluster stopped successfully!" -ForegroundColor Green
        Write-Host "`nBilling impact:" -ForegroundColor Cyan
        Write-Host "  - AKS compute: PAUSED (saves ~`$85/month)" -ForegroundColor Green
        Write-Host "  - Storage/disks: Still billed (~`$2/month)" -ForegroundColor Yellow
        Write-Host "  - Redis/Event Hubs: Still billed (~`$27/month)" -ForegroundColor Yellow
        Write-Host "`nTo restart: ./cluster-control.ps1 -ResourceGroup $ResourceGroup -Action start" -ForegroundColor Cyan
    }

    "start" {
        Write-Host "Starting cluster..." -ForegroundColor Yellow
        Write-Host "This may take 2-5 minutes.`n" -ForegroundColor White

        az aks start --resource-group $ResourceGroup --name $aksName

        Write-Host "`nCluster started successfully!" -ForegroundColor Green
        Write-Host "`nGetting credentials..." -ForegroundColor Cyan
        az aks get-credentials --resource-group $ResourceGroup --name $aksName --overwrite-existing

        Write-Host "`nVerifying cluster:" -ForegroundColor Cyan
        kubectl get nodes

        Write-Host "`nCluster is ready. Full billing resumed." -ForegroundColor Yellow
    }
}
