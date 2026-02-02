#!/bin/bash
# OpenFrame Azure Deployment Script
# Usage: ./deploy.sh <environment> <resource-group> <location>

set -e

# Arguments
ENVIRONMENT=${1:-test}
RESOURCE_GROUP=${2:-openframe-test}
LOCATION=${3:-eastus}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Environment configurations
declare -A CONFIG

case $ENVIRONMENT in
    test)
        CONFIG[aks_node_count]=1
        CONFIG[aks_node_size]="Standard_B4ms"
        CONFIG[aks_min_nodes]=1
        CONFIG[aks_max_nodes]=2
        CONFIG[cosmos_mode]="Serverless"
        CONFIG[cosmos_ru]=0
        CONFIG[redis_size]="C0"
        CONFIG[redis_sku]="Basic"
        CONFIG[eventhubs_tier]="Basic"
        CONFIG[eventhubs_capacity]=1
        CONFIG[acr_sku]="Basic"
        CONFIG[enable_monitoring]="false"
        CONFIG[enable_ha]="false"
        ;;
    dev)
        CONFIG[aks_node_count]=2
        CONFIG[aks_node_size]="Standard_B4ms"
        CONFIG[aks_min_nodes]=2
        CONFIG[aks_max_nodes]=4
        CONFIG[cosmos_mode]="Provisioned"
        CONFIG[cosmos_ru]=1000
        CONFIG[redis_size]="C1"
        CONFIG[redis_sku]="Standard"
        CONFIG[eventhubs_tier]="Standard"
        CONFIG[eventhubs_capacity]=1
        CONFIG[acr_sku]="Standard"
        CONFIG[enable_monitoring]="true"
        CONFIG[enable_ha]="false"
        ;;
    prod)
        CONFIG[aks_node_count]=3
        CONFIG[aks_node_size]="Standard_D4s_v5"
        CONFIG[aks_min_nodes]=3
        CONFIG[aks_max_nodes]=10
        CONFIG[cosmos_mode]="Autoscale"
        CONFIG[cosmos_ru]=4000
        CONFIG[redis_size]="C1"
        CONFIG[redis_sku]="Premium"
        CONFIG[eventhubs_tier]="Standard"
        CONFIG[eventhubs_capacity]=2
        CONFIG[acr_sku]="Standard"
        CONFIG[enable_monitoring]="true"
        CONFIG[enable_ha]="true"
        ;;
    *)
        echo -e "${RED}Invalid environment: $ENVIRONMENT. Use test, dev, or prod.${NC}"
        exit 1
        ;;
esac

# Naming conventions
NAMING_PREFIX="of-${ENVIRONMENT}"
AKS_NAME="${NAMING_PREFIX}-aks"
ACR_NAME="of${ENVIRONMENT}acr$RANDOM"
VNET_NAME="${NAMING_PREFIX}-vnet"
KEYVAULT_NAME="${NAMING_PREFIX}-kv-$RANDOM"
COSMOSDB_NAME="${NAMING_PREFIX}-cosmos"
REDIS_NAME="${NAMING_PREFIX}-redis"
EVENTHUBS_NAME="${NAMING_PREFIX}-eventhubs"
STORAGE_NAME="of${ENVIRONMENT}storage$RANDOM"

write_step() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

check_prerequisites() {
    write_step "Checking Prerequisites"

    for tool in az kubectl helm; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}$tool is required but not installed.${NC}"
            exit 1
        fi
        echo -e "  ${GREEN}[OK]${NC} $tool found"
    done

    # Check Azure login
    if ! az account show &> /dev/null; then
        echo -e "${RED}Not logged into Azure. Run 'az login' first.${NC}"
        exit 1
    fi
    ACCOUNT=$(az account show --query user.name -o tsv)
    echo -e "  ${GREEN}[OK]${NC} Logged in as: $ACCOUNT"
}

create_resource_group() {
    write_step "Creating Resource Group"

    if [ "$(az group exists --name $RESOURCE_GROUP)" = "false" ]; then
        az group create \
            --name $RESOURCE_GROUP \
            --location $LOCATION \
            --tags Environment=$ENVIRONMENT Project=OpenFrame
        echo -e "  ${GREEN}Created resource group: $RESOURCE_GROUP${NC}"
    else
        echo -e "  ${YELLOW}Resource group already exists: $RESOURCE_GROUP${NC}"
    fi
}

create_virtual_network() {
    write_step "Creating Virtual Network"

    az network vnet create \
        --resource-group $RESOURCE_GROUP \
        --name $VNET_NAME \
        --address-prefix "10.0.0.0/16" \
        --subnet-name "aks-subnet" \
        --subnet-prefix "10.0.0.0/22" \
        --tags Environment=$ENVIRONMENT

    az network vnet subnet create \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name "db-subnet" \
        --address-prefix "10.0.4.0/24"

    echo -e "  ${GREEN}Created VNet: $VNET_NAME${NC}"
}

create_container_registry() {
    write_step "Creating Container Registry"

    az acr create \
        --resource-group $RESOURCE_GROUP \
        --name $ACR_NAME \
        --sku ${CONFIG[acr_sku]} \
        --tags Environment=$ENVIRONMENT

    echo -e "  ${GREEN}Created ACR: $ACR_NAME${NC}"
}

create_key_vault() {
    write_step "Creating Key Vault"

    az keyvault create \
        --resource-group $RESOURCE_GROUP \
        --name $KEYVAULT_NAME \
        --location $LOCATION \
        --enable-rbac-authorization true \
        --tags Environment=$ENVIRONMENT

    echo -e "  ${GREEN}Created Key Vault: $KEYVAULT_NAME${NC}"
}

create_aks_cluster() {
    write_step "Creating AKS Cluster"

    SUBNET_ID=$(az network vnet subnet show \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name "aks-subnet" \
        --query id -o tsv)

    AKS_ARGS=(
        "--resource-group" "$RESOURCE_GROUP"
        "--name" "$AKS_NAME"
        "--location" "$LOCATION"
        "--node-count" "${CONFIG[aks_node_count]}"
        "--node-vm-size" "${CONFIG[aks_node_size]}"
        "--enable-managed-identity"
        "--network-plugin" "azure"
        "--vnet-subnet-id" "$SUBNET_ID"
        "--dns-service-ip" "10.0.8.10"
        "--service-cidr" "10.0.8.0/24"
        "--generate-ssh-keys"
        "--attach-acr" "$ACR_NAME"
        "--enable-cluster-autoscaler"
        "--min-count" "${CONFIG[aks_min_nodes]}"
        "--max-count" "${CONFIG[aks_max_nodes]}"
        "--tags" "Environment=$ENVIRONMENT"
    )

    if [ "${CONFIG[enable_monitoring]}" = "true" ]; then
        AKS_ARGS+=("--enable-addons" "monitoring")
    fi

    az aks create "${AKS_ARGS[@]}"

    # Get credentials
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing

    echo -e "  ${GREEN}Created AKS: $AKS_NAME${NC}"
}

create_cosmos_db() {
    write_step "Creating Cosmos DB (MongoDB API)"

    COSMOS_ARGS=(
        "--resource-group" "$RESOURCE_GROUP"
        "--name" "$COSMOSDB_NAME"
        "--kind" "MongoDB"
        "--server-version" "7.0"
        "--default-consistency-level" "Session"
        "--locations" "regionName=$LOCATION failoverPriority=0 isZoneRedundant=${CONFIG[enable_ha]}"
        "--tags" "Environment=$ENVIRONMENT"
    )

    if [ "${CONFIG[cosmos_mode]}" = "Serverless" ]; then
        COSMOS_ARGS+=("--capabilities" "EnableServerless")
    fi

    az cosmosdb create "${COSMOS_ARGS[@]}"

    az cosmosdb mongodb database create \
        --resource-group $RESOURCE_GROUP \
        --account-name $COSMOSDB_NAME \
        --name "openframe"

    MONGO_CONN=$(az cosmosdb keys list \
        --resource-group $RESOURCE_GROUP \
        --name $COSMOSDB_NAME \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" -o tsv)

    echo -e "  ${GREEN}Created Cosmos DB: $COSMOSDB_NAME${NC}"
}

create_redis_cache() {
    write_step "Creating Azure Cache for Redis"

    az redis create \
        --resource-group $RESOURCE_GROUP \
        --name $REDIS_NAME \
        --location $LOCATION \
        --sku ${CONFIG[redis_sku]} \
        --vm-size ${CONFIG[redis_size]} \
        --tags Environment=$ENVIRONMENT

    REDIS_HOST=$(az redis show --resource-group $RESOURCE_GROUP --name $REDIS_NAME --query hostName -o tsv)
    REDIS_KEY=$(az redis list-keys --resource-group $RESOURCE_GROUP --name $REDIS_NAME --query primaryKey -o tsv)

    echo -e "  ${GREEN}Created Redis: $REDIS_NAME${NC}"
}

create_event_hubs() {
    write_step "Creating Event Hubs (Kafka-compatible)"

    az eventhubs namespace create \
        --resource-group $RESOURCE_GROUP \
        --name $EVENTHUBS_NAME \
        --location $LOCATION \
        --sku ${CONFIG[eventhubs_tier]} \
        --capacity ${CONFIG[eventhubs_capacity]} \
        --enable-kafka true \
        --tags Environment=$ENVIRONMENT

    # Create required topics
    for topic in pinot-events devices-topic integrated-tool-events fleet-activities; do
        az eventhubs eventhub create \
            --resource-group $RESOURCE_GROUP \
            --namespace-name $EVENTHUBS_NAME \
            --name $topic \
            --partition-count 2 \
            --message-retention 1
    done

    KAFKA_CONN=$(az eventhubs namespace authorization-rule keys list \
        --resource-group $RESOURCE_GROUP \
        --namespace-name $EVENTHUBS_NAME \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString -o tsv)

    echo -e "  ${GREEN}Created Event Hubs: $EVENTHUBS_NAME${NC}"
}

create_storage_account() {
    write_step "Creating Storage Account"

    if [ "${CONFIG[enable_ha]}" = "true" ]; then
        REDUNDANCY="ZRS"
    else
        REDUNDANCY="LRS"
    fi

    az storage account create \
        --resource-group $RESOURCE_GROUP \
        --name $STORAGE_NAME \
        --location $LOCATION \
        --sku "Standard_$REDUNDANCY" \
        --kind StorageV2 \
        --tags Environment=$ENVIRONMENT

    echo -e "  ${GREEN}Created Storage: $STORAGE_NAME${NC}"
}

install_kubernetes_resources() {
    write_step "Installing Kubernetes Resources"

    # Create namespaces
    for ns in openframe datasources integrated-tools monitoring; do
        kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
    done

    # Create secrets
    kubectl create secret generic openframe-secrets \
        --namespace openframe \
        --from-literal=mongodb-uri="$MONGO_CONN" \
        --from-literal=redis-host="$REDIS_HOST" \
        --from-literal=redis-password="$REDIS_KEY" \
        --from-literal=kafka-connection="$KAFKA_CONN" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Install NGINX Ingress Controller
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.externalTrafficPolicy=Local

    # Deploy OpenFrame services
    VALUES_FILE="$SCRIPT_DIR/../configs/helm-values/${ENVIRONMENT}-values.yaml"
    MANIFESTS_PATH="$PROJECT_ROOT/manifests"

    SERVICES=(
        "microservices/openframe-config"
        "microservices/openframe-gateway"
        "microservices/openframe-api"
        "microservices/openframe-stream"
        "microservices/openframe-management"
        "microservices/openframe-client"
        "microservices/openframe-frontend"
    )

    for service in "${SERVICES[@]}"; do
        CHART_PATH="$MANIFESTS_PATH/$service"
        RELEASE_NAME=$(basename $service)

        if [ -d "$CHART_PATH" ]; then
            echo -e "  ${YELLOW}Deploying $RELEASE_NAME...${NC}"
            if [ -f "$VALUES_FILE" ]; then
                helm upgrade --install $RELEASE_NAME $CHART_PATH \
                    --namespace openframe \
                    --values $VALUES_FILE \
                    --wait --timeout 5m0s
            else
                helm upgrade --install $RELEASE_NAME $CHART_PATH \
                    --namespace openframe \
                    --wait --timeout 5m0s
            fi
        fi
    done

    echo -e "  ${GREEN}Kubernetes resources deployed${NC}"
}

show_summary() {
    write_step "Deployment Summary"

    INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    echo "Environment:     $ENVIRONMENT"
    echo "Resource Group:  $RESOURCE_GROUP"
    echo "Location:        $LOCATION"
    echo ""
    echo -e "${YELLOW}Resources Created:${NC}"
    echo "  AKS Cluster:   $AKS_NAME"
    echo "  ACR:           $ACR_NAME"
    echo "  Key Vault:     $KEYVAULT_NAME"
    echo "  Cosmos DB:     $COSMOSDB_NAME"
    echo "  Redis:         $REDIS_NAME"
    echo "  Event Hubs:    $EVENTHUBS_NAME"
    echo ""
    echo -e "${YELLOW}Access:${NC}"
    if [ -n "$INGRESS_IP" ]; then
        echo -e "  Load Balancer IP: ${GREEN}$INGRESS_IP${NC}"
        echo -e "  Dashboard URL:    ${GREEN}http://$INGRESS_IP${NC}"
    else
        echo "  Run 'kubectl get svc -n ingress-nginx' to get the external IP"
    fi
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Configure DNS to point to the Load Balancer IP"
    echo "  2. Set up TLS certificates with cert-manager"
    echo "  3. Change default admin password"
}

# Main execution
main() {
    echo -e "\n${CYAN}OpenFrame Azure Deployment${NC}"
    echo -e "${CYAN}Environment: $ENVIRONMENT | Location: $LOCATION${NC}\n"

    check_prerequisites
    create_resource_group
    create_virtual_network
    create_container_registry
    create_key_vault
    create_aks_cluster
    create_cosmos_db
    create_redis_cache
    create_event_hubs
    create_storage_account
    install_kubernetes_resources
    show_summary
}

main
