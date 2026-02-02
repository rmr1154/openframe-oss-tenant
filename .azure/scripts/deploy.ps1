<#
.SYNOPSIS
    Deploy OpenFrame platform to Azure.

.DESCRIPTION
    This script provisions all Azure resources and deploys the OpenFrame platform
    using AKS, Cosmos DB, Azure Cache for Redis, and Event Hubs.

.PARAMETER Environment
    Target environment: test, dev, or prod

.PARAMETER ResourceGroup
    Name of the Azure Resource Group

.PARAMETER Location
    Azure region for deployment

.PARAMETER SubscriptionId
    Azure Subscription ID (optional, uses current context if not specified)

.PARAMETER Upgrade
    Upgrade existing deployment instead of fresh install

.EXAMPLE
    ./deploy.ps1 -Environment test -ResourceGroup openframe-test -Location eastus
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("eval", "test", "dev", "prod")]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$Upgrade,

    [Parameter(Mandatory = $false)]
    [switch]$SkipInfrastructure,

    [Parameter(Mandatory = $false)]
    [switch]$SkipKubernetes
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptRoot)

# Environment configurations
$EnvConfigs = @{
    eval = @{
        AksNodeCount      = 1
        AksNodeSize       = "Standard_B4ms"
        AksMinNodes       = 1
        AksMaxNodes       = 1
        CosmosDbMode      = "None"  # Self-hosted on AKS
        CosmosDbRU        = 0
        RedisSize         = "None"  # Self-hosted on AKS
        RedisSku          = "None"
        EventHubsTier     = "None"  # Self-hosted Kafka on AKS
        EventHubsCapacity = 0
        AcrSku            = "Basic"
        EnableMonitoring  = $false
        EnableHA          = $false
        SelfHostedData    = $true
    }
    test = @{
        AksNodeCount      = 1
        AksNodeSize       = "Standard_B4ms"
        AksMinNodes       = 1
        AksMaxNodes       = 2
        CosmosDbMode      = "Serverless"
        CosmosDbRU        = 0
        RedisSize         = "C0"
        RedisSku          = "Basic"
        EventHubsTier     = "Basic"
        EventHubsCapacity = 1
        AcrSku            = "Basic"
        EnableMonitoring  = $false
        EnableHA          = $false
        SelfHostedData    = $false
    }
    dev  = @{
        AksNodeCount      = 2
        AksNodeSize       = "Standard_B4ms"
        AksMinNodes       = 2
        AksMaxNodes       = 4
        CosmosDbMode      = "Provisioned"
        CosmosDbRU        = 1000
        RedisSize         = "C1"
        RedisSku          = "Standard"
        EventHubsTier     = "Standard"
        EventHubsCapacity = 1
        AcrSku            = "Standard"
        EnableMonitoring  = $true
        EnableHA          = $false
    }
    prod = @{
        AksNodeCount      = 3
        AksNodeSize       = "Standard_D4s_v5"
        AksMinNodes       = 3
        AksMaxNodes       = 10
        CosmosDbMode      = "Autoscale"
        CosmosDbRU        = 4000
        RedisSize         = "C1"
        RedisSku          = "Premium"
        EventHubsTier     = "Standard"
        EventHubsCapacity = 2
        AcrSku            = "Standard"
        EnableMonitoring  = $true
        EnableHA          = $true
    }
}

$Config = $EnvConfigs[$Environment]

# Naming conventions
$NamingPrefix = "of-$Environment"
$AksName = "$NamingPrefix-aks"
$AcrName = "of${Environment}acr$(Get-Random -Maximum 9999)"
$VNetName = "$NamingPrefix-vnet"
$KeyVaultName = "$NamingPrefix-kv-$(Get-Random -Maximum 999)"
$CosmosDbName = "$NamingPrefix-cosmos"
$RedisName = "$NamingPrefix-redis"
$EventHubsName = "$NamingPrefix-eventhubs"
$StorageAccountName = "of${Environment}storage$(Get-Random -Maximum 999)"

function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Test-Prerequisites {
    Write-Step "Checking Prerequisites"

    $tools = @("az", "kubectl", "helm")
    foreach ($tool in $tools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "$tool is required but not installed."
        }
        Write-Host "  [OK] $tool found" -ForegroundColor Green
    }

    # Check Azure login
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "Not logged into Azure. Run 'az login' first."
    }
    Write-Host "  [OK] Logged in as: $($account.user.name)" -ForegroundColor Green
}

function Set-Subscription {
    if ($SubscriptionId) {
        Write-Step "Setting Subscription"
        az account set --subscription $SubscriptionId
        Write-Host "  Using subscription: $SubscriptionId" -ForegroundColor Green
    }
}

function New-ResourceGroup {
    Write-Step "Creating Resource Group"

    $exists = az group exists --name $ResourceGroup
    if ($exists -eq "false") {
        az group create --name $ResourceGroup --location $Location --tags Environment=$Environment Project=OpenFrame
        Write-Host "  Created resource group: $ResourceGroup" -ForegroundColor Green
    }
    else {
        Write-Host "  Resource group already exists: $ResourceGroup" -ForegroundColor Yellow
    }
}

function New-VirtualNetwork {
    Write-Step "Creating Virtual Network"

    az network vnet create `
        --resource-group $ResourceGroup `
        --name $VNetName `
        --address-prefix "10.0.0.0/16" `
        --subnet-name "aks-subnet" `
        --subnet-prefix "10.0.0.0/22" `
        --tags Environment=$Environment

    # Create subnet for databases (private endpoints)
    az network vnet subnet create `
        --resource-group $ResourceGroup `
        --vnet-name $VNetName `
        --name "db-subnet" `
        --address-prefix "10.0.4.0/24"

    Write-Host "  Created VNet: $VNetName" -ForegroundColor Green
}

function New-ContainerRegistry {
    Write-Step "Creating Container Registry"

    az acr create `
        --resource-group $ResourceGroup `
        --name $AcrName `
        --sku $Config.AcrSku `
        --tags Environment=$Environment

    Write-Host "  Created ACR: $AcrName" -ForegroundColor Green
    return $AcrName
}

function New-KeyVault {
    Write-Step "Creating Key Vault"

    az keyvault create `
        --resource-group $ResourceGroup `
        --name $KeyVaultName `
        --location $Location `
        --enable-rbac-authorization true `
        --tags Environment=$Environment

    Write-Host "  Created Key Vault: $KeyVaultName" -ForegroundColor Green
    return $KeyVaultName
}

function New-AksCluster {
    param([string]$AcrName)

    Write-Step "Creating AKS Cluster"

    $subnetId = $(az network vnet subnet show `
            --resource-group $ResourceGroup `
            --vnet-name $VNetName `
            --name "aks-subnet" `
            --query id -o tsv)

    $aksParams = @(
        "--resource-group", $ResourceGroup,
        "--name", $AksName,
        "--location", $Location,
        "--node-count", $Config.AksNodeCount,
        "--node-vm-size", $Config.AksNodeSize,
        "--enable-managed-identity",
        "--network-plugin", "azure",
        "--vnet-subnet-id", $subnetId,
        "--dns-service-ip", "10.0.8.10",
        "--service-cidr", "10.0.8.0/24",
        "--generate-ssh-keys",
        "--attach-acr", $AcrName,
        "--enable-cluster-autoscaler",
        "--min-count", $Config.AksMinNodes,
        "--max-count", $Config.AksMaxNodes,
        "--tags", "Environment=$Environment"
    )

    if ($Config.EnableMonitoring) {
        $aksParams += "--enable-addons", "monitoring"
    }

    az aks create @aksParams

    # Get credentials
    az aks get-credentials --resource-group $ResourceGroup --name $AksName --overwrite-existing

    Write-Host "  Created AKS: $AksName" -ForegroundColor Green
}

function New-CosmosDb {
    Write-Step "Creating Cosmos DB (MongoDB API)"

    # Create Cosmos DB account with MongoDB API
    $cosmosParams = @(
        "--resource-group", $ResourceGroup,
        "--name", $CosmosDbName,
        "--kind", "MongoDB",
        "--server-version", "7.0",
        "--default-consistency-level", "Session",
        "--locations", "regionName=$Location failoverPriority=0 isZoneRedundant=$($Config.EnableHA)",
        "--tags", "Environment=$Environment"
    )

    if ($Config.CosmosDbMode -eq "Serverless") {
        $cosmosParams += "--capabilities", "EnableServerless"
    }

    az cosmosdb create @cosmosParams

    # Create database
    az cosmosdb mongodb database create `
        --resource-group $ResourceGroup `
        --account-name $CosmosDbName `
        --name "openframe"

    # Get connection string
    $connString = az cosmosdb keys list `
        --resource-group $ResourceGroup `
        --name $CosmosDbName `
        --type connection-strings `
        --query "connectionStrings[0].connectionString" -o tsv

    Write-Host "  Created Cosmos DB: $CosmosDbName" -ForegroundColor Green
    return $connString
}

function New-RedisCache {
    Write-Step "Creating Azure Cache for Redis"

    az redis create `
        --resource-group $ResourceGroup `
        --name $RedisName `
        --location $Location `
        --sku $Config.RedisSku `
        --vm-size $Config.RedisSize `
        --tags Environment=$Environment

    # Get connection details
    $redisHost = az redis show --resource-group $ResourceGroup --name $RedisName --query hostName -o tsv
    $redisKey = az redis list-keys --resource-group $ResourceGroup --name $RedisName --query primaryKey -o tsv

    Write-Host "  Created Redis: $RedisName" -ForegroundColor Green
    return @{Host = $redisHost; Key = $redisKey }
}

function New-EventHubs {
    Write-Step "Creating Event Hubs (Kafka-compatible)"

    # Create Event Hubs namespace
    az eventhubs namespace create `
        --resource-group $ResourceGroup `
        --name $EventHubsName `
        --location $Location `
        --sku $Config.EventHubsTier `
        --capacity $Config.EventHubsCapacity `
        --enable-kafka true `
        --tags Environment=$Environment

    # Create required topics (Event Hubs)
    $topics = @("pinot-events", "devices-topic", "integrated-tool-events", "fleet-activities")
    foreach ($topic in $topics) {
        az eventhubs eventhub create `
            --resource-group $ResourceGroup `
            --namespace-name $EventHubsName `
            --name $topic `
            --partition-count 2 `
            --message-retention 1
    }

    # Get connection string
    $connString = az eventhubs namespace authorization-rule keys list `
        --resource-group $ResourceGroup `
        --namespace-name $EventHubsName `
        --name RootManageSharedAccessKey `
        --query primaryConnectionString -o tsv

    Write-Host "  Created Event Hubs: $EventHubsName" -ForegroundColor Green
    return $connString
}

function New-StorageAccount {
    Write-Step "Creating Storage Account"

    $redundancy = if ($Config.EnableHA) { "ZRS" } else { "LRS" }

    az storage account create `
        --resource-group $ResourceGroup `
        --name $StorageAccountName `
        --location $Location `
        --sku "Standard_$redundancy" `
        --kind StorageV2 `
        --tags Environment=$Environment

    Write-Host "  Created Storage: $StorageAccountName" -ForegroundColor Green
}

function Install-KubernetesResources {
    param(
        [string]$MongoConnString,
        [hashtable]$RedisConfig,
        [string]$KafkaConnString
    )

    Write-Step "Installing Kubernetes Resources"

    # Create namespaces
    $namespaces = @("openframe", "datasources", "integrated-tools", "monitoring")
    foreach ($ns in $namespaces) {
        kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
    }

    # Create secrets
    kubectl create secret generic openframe-secrets `
        --namespace openframe `
        --from-literal=mongodb-uri="$MongoConnString" `
        --from-literal=redis-host="$($RedisConfig.Host)" `
        --from-literal=redis-password="$($RedisConfig.Key)" `
        --from-literal=kafka-connection="$KafkaConnString" `
        --dry-run=client -o yaml | kubectl apply -f -

    # Install NGINX Ingress Controller
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
        --namespace ingress-nginx `
        --create-namespace `
        --set controller.service.externalTrafficPolicy=Local

    # Apply Helm values based on environment
    $valuesFile = Join-Path $ScriptRoot ".." "configs" "helm-values" "$Environment-values.yaml"

    # Deploy OpenFrame services using existing Helm charts
    $manifestsPath = Join-Path $ProjectRoot "manifests"

    # Deploy core services
    $services = @(
        "microservices/openframe-config",
        "microservices/openframe-gateway",
        "microservices/openframe-api",
        "microservices/openframe-stream",
        "microservices/openframe-management",
        "microservices/openframe-client",
        "microservices/openframe-frontend"
    )

    foreach ($service in $services) {
        $chartPath = Join-Path $manifestsPath $service
        $releaseName = Split-Path $service -Leaf

        if (Test-Path $chartPath) {
            Write-Host "  Deploying $releaseName..." -ForegroundColor Yellow
            if (Test-Path $valuesFile) {
                helm upgrade --install $releaseName $chartPath `
                    --namespace openframe `
                    --values $valuesFile `
                    --wait --timeout 5m0s
            }
            else {
                helm upgrade --install $releaseName $chartPath `
                    --namespace openframe `
                    --wait --timeout 5m0s
            }
        }
    }

    Write-Host "  Kubernetes resources deployed" -ForegroundColor Green
}

function Show-DeploymentSummary {
    param(
        [string]$AcrName,
        [string]$KeyVaultName
    )

    Write-Step "Deployment Summary"

    $ingressIp = kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null

    Write-Host "Environment:     $Environment" -ForegroundColor White
    Write-Host "Resource Group:  $ResourceGroup" -ForegroundColor White
    Write-Host "Location:        $Location" -ForegroundColor White
    Write-Host ""
    Write-Host "Resources Created:" -ForegroundColor Yellow
    Write-Host "  AKS Cluster:   $AksName" -ForegroundColor White
    Write-Host "  ACR:           $AcrName" -ForegroundColor White
    Write-Host "  Key Vault:     $KeyVaultName" -ForegroundColor White
    Write-Host "  Cosmos DB:     $CosmosDbName" -ForegroundColor White
    Write-Host "  Redis:         $RedisName" -ForegroundColor White
    Write-Host "  Event Hubs:    $EventHubsName" -ForegroundColor White
    Write-Host ""
    Write-Host "Access:" -ForegroundColor Yellow
    if ($ingressIp) {
        Write-Host "  Load Balancer IP: $ingressIp" -ForegroundColor Green
        Write-Host "  Dashboard URL:    http://$ingressIp" -ForegroundColor Green
    }
    else {
        Write-Host "  Run 'kubectl get svc -n ingress-nginx' to get the external IP" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure DNS to point to the Load Balancer IP" -ForegroundColor White
    Write-Host "  2. Set up TLS certificates with cert-manager" -ForegroundColor White
    Write-Host "  3. Change default admin password" -ForegroundColor White
}

# Main execution
try {
    Write-Host "`nOpenFrame Azure Deployment" -ForegroundColor Magenta
    Write-Host "Environment: $Environment | Location: $Location`n" -ForegroundColor Magenta

    Test-Prerequisites
    Set-Subscription

    if (-not $SkipInfrastructure) {
        New-ResourceGroup
        New-VirtualNetwork
        $createdAcr = New-ContainerRegistry
        $createdKv = New-KeyVault
        New-AksCluster -AcrName $createdAcr
        $mongoConn = New-CosmosDb
        $redisConfig = New-RedisCache
        $kafkaConn = New-EventHubs
        New-StorageAccount
    }

    if (-not $SkipKubernetes) {
        # Retrieve connection strings if skipped infrastructure
        if ($SkipInfrastructure) {
            $mongoConn = az cosmosdb keys list --resource-group $ResourceGroup --name $CosmosDbName --type connection-strings --query "connectionStrings[0].connectionString" -o tsv
            $redisHost = az redis show --resource-group $ResourceGroup --name $RedisName --query hostName -o tsv
            $redisKey = az redis list-keys --resource-group $ResourceGroup --name $RedisName --query primaryKey -o tsv
            $redisConfig = @{Host = $redisHost; Key = $redisKey }
            $kafkaConn = az eventhubs namespace authorization-rule keys list --resource-group $ResourceGroup --namespace-name $EventHubsName --name RootManageSharedAccessKey --query primaryConnectionString -o tsv
        }

        Install-KubernetesResources -MongoConnString $mongoConn -RedisConfig $redisConfig -KafkaConnString $kafkaConn
    }

    Show-DeploymentSummary -AcrName $createdAcr -KeyVaultName $createdKv
}
catch {
    Write-Host "`nDeployment failed: $_" -ForegroundColor Red
    exit 1
}
