<#
.SYNOPSIS
    Destroy OpenFrame Azure deployment.

.DESCRIPTION
    This script removes all Azure resources created for OpenFrame deployment.

.PARAMETER ResourceGroup
    Name of the Azure Resource Group to delete

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    ./destroy.ps1 -ResourceGroup openframe-test
    ./destroy.ps1 -ResourceGroup openframe-test -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

Write-Step "OpenFrame Azure Cleanup"

# Check if resource group exists
$exists = az group exists --name $ResourceGroup
if ($exists -eq "false") {
    Write-Host "Resource group '$ResourceGroup' does not exist." -ForegroundColor Yellow
    exit 0
}

# List resources
Write-Host "Resources in '$ResourceGroup':" -ForegroundColor Yellow
az resource list --resource-group $ResourceGroup --output table

if (-not $Force) {
    Write-Host "`nThis will permanently delete ALL resources in the resource group." -ForegroundColor Red
    $confirmation = Read-Host "Type 'yes' to confirm deletion"
    if ($confirmation -ne "yes") {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

Write-Step "Deleting Resource Group"

# Delete AKS cluster first to avoid orphaned resources
$aksName = az aks list --resource-group $ResourceGroup --query "[0].name" -o tsv 2>$null
if ($aksName) {
    Write-Host "  Deleting AKS cluster: $aksName" -ForegroundColor Yellow
    az aks delete --resource-group $ResourceGroup --name $aksName --yes --no-wait
}

# Delete the resource group
Write-Host "  Deleting resource group: $ResourceGroup" -ForegroundColor Yellow
az group delete --name $ResourceGroup --yes --no-wait

Write-Host "`nDeletion initiated. Resources will be removed in the background." -ForegroundColor Green
Write-Host "Run 'az group show -n $ResourceGroup' to check status." -ForegroundColor Cyan
