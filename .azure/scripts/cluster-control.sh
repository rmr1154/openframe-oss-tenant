#!/bin/bash
# Start or stop OpenFrame AKS cluster to manage costs
# Usage: ./cluster-control.sh <resource-group> <start|stop|status>

set -e

RESOURCE_GROUP=${1:-}
ACTION=${2:-}

if [ -z "$RESOURCE_GROUP" ] || [ -z "$ACTION" ]; then
    echo "Usage: ./cluster-control.sh <resource-group> <start|stop|status>"
    exit 1
fi

# Find AKS cluster
AKS_NAME=$(az aks list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)
if [ -z "$AKS_NAME" ]; then
    echo "No AKS cluster found in resource group: $RESOURCE_GROUP"
    exit 1
fi

echo ""
echo "OpenFrame Cluster Control"
echo "Cluster: $AKS_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

case $ACTION in
    status)
        POWER_STATE=$(az aks show --resource-group $RESOURCE_GROUP --name $AKS_NAME --query "powerState.code" -o tsv)

        echo -n "Status: "
        if [ "$POWER_STATE" = "Running" ]; then
            echo -e "\033[0;32mRUNNING\033[0m"
            echo ""
            echo "Cluster is active and billing for compute."
        elif [ "$POWER_STATE" = "Stopped" ]; then
            echo -e "\033[0;31mSTOPPED\033[0m"
            echo ""
            echo "Compute billing is paused. Storage costs still apply."
        else
            echo "$POWER_STATE"
        fi

        echo ""
        echo "Node Pools:"
        az aks nodepool list --resource-group $RESOURCE_GROUP --cluster-name $AKS_NAME \
            --query "[].{name:name, count:count, vmSize:vmSize}" -o table
        ;;

    stop)
        echo "Stopping cluster..."
        echo "This will deallocate all nodes and pause compute billing."
        echo ""

        az aks stop --resource-group $RESOURCE_GROUP --name $AKS_NAME

        echo ""
        echo "Cluster stopped successfully!"
        echo ""
        echo "Billing impact:"
        echo "  - AKS compute: PAUSED (saves ~\$85/month)"
        echo "  - Storage/disks: Still billed (~\$2/month)"
        echo "  - Redis/Event Hubs: Still billed (~\$27/month)"
        echo ""
        echo "To restart: ./cluster-control.sh $RESOURCE_GROUP start"
        ;;

    start)
        echo "Starting cluster..."
        echo "This may take 2-5 minutes."
        echo ""

        az aks start --resource-group $RESOURCE_GROUP --name $AKS_NAME

        echo ""
        echo "Cluster started successfully!"
        echo ""
        echo "Getting credentials..."
        az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing

        echo ""
        echo "Verifying cluster:"
        kubectl get nodes

        echo ""
        echo "Cluster is ready. Full billing resumed."
        ;;

    *)
        echo "Invalid action: $ACTION"
        echo "Valid actions: start, stop, status"
        exit 1
        ;;
esac
