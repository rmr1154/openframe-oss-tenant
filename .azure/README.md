# OpenFrame Azure Deployment

This folder contains scripts and configurations for deploying OpenFrame on Microsoft Azure.

## Before You Start: Consider Local Development

**For evaluation and testing, you don't need Azure at all.** The platform runs on Docker Desktop or Kind (Kubernetes in Docker) at **zero cost**:

```bash
# From the project root - uses Kind/Docker Desktop
./run.sh bootstrap    # Full cluster setup
./run.sh up           # Start cluster
./run.sh app all      # Deploy all apps
```

**Local Requirements:**
- Docker Desktop with Kubernetes enabled (or Kind)
- 16GB RAM allocated to Docker
- 4+ CPU cores
- 50GB disk space

**Use Azure when you need:**
- Shared team environments
- CI/CD pipelines
- Pre-production staging
- Production deployments

---

## Architecture Overview

The Azure deployment uses the following services:

| Component | Azure Service | Test Tier | Production Tier |
|-----------|--------------|-----------|-----------------|
| Kubernetes | AKS | Standard_B4ms (1 node) | Standard_D4s_v5 (3+ nodes) |
| Container Registry | ACR | Basic | Standard |
| MongoDB | Cosmos DB (MongoDB API) | Serverless | Autoscale (4000 RU/s) |
| Redis | Azure Cache for Redis | Basic C0 | Standard C1 |
| Kafka | Azure Event Hubs | Basic | Standard |
| Storage | Azure Blob Storage | LRS | ZRS |
| Key Vault | Azure Key Vault | Standard | Standard |
| Monitoring | Azure Monitor + Grafana | Basic | Full stack |

## Prerequisites

- Azure CLI 2.50+ installed (`az --version`)
- PowerShell 7+ or Bash
- kubectl installed
- Helm 3.x installed
- Azure subscription with appropriate permissions

## Quick Start (Test Environment)

```powershell
# Login to Azure
az login

# Set subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Deploy test environment (minimal cost)
./scripts/deploy.ps1 -Environment test -ResourceGroup openframe-test -Location eastus

# Or using Bash
./scripts/deploy.sh test openframe-test eastus
```

## Deployment Options

| Environment | Monthly Cost | Use Case |
|-------------|-------------|----------|
| **Local (Docker/Kind)** | **$0** | Evaluation, demos, local dev |
| **Eval (Azure)** | ~$100-130 | Shared testing, all self-hosted |
| **Test (Azure)** | ~$150-250 | Team testing, managed DBs |
| **Dev (Azure)** | ~$350-500 | Active development, staging |
| **Prod (Azure)** | ~$1,500-3,000 | Production workloads |

### Local / Docker Desktop ($0)
- Use existing `./run.sh` scripts
- All services run in Docker/Kind
- Best for: Individual evaluation, demos

### Eval Environment (~$100-130/month)
- Single AKS node (B4ms - 4 vCPU, 16GB RAM)
- **All databases self-hosted on AKS** (no Cosmos DB, no Azure Redis)
- No monitoring stack
- Estimated cost breakdown:
  - AKS node: ~$85
  - ACR Basic: ~$5
  - Load Balancer: ~$18
  - Storage/bandwidth: ~$2

### Test Environment (~$150-250/month)
- Single AKS node (B4ms - 4 vCPU, 16GB RAM)
- Cosmos DB Serverless (pay per request)
- Azure Cache for Redis Basic
- Event Hubs Basic
- No high availability

### Development Environment (~$350-500/month)
- 2-node AKS cluster (B4ms)
- Cosmos DB with 1000 RU/s provisioned
- Standard tier for critical services

### Production Environment (~$1,500-3,000/month)
- 3+ node AKS cluster with autoscaling (D4s_v5)
- Cosmos DB with autoscale (4000 RU/s max)
- Premium/Standard tier services
- Multi-zone redundancy

## Directory Structure

```
.azure/
├── README.md                    # This file
├── scripts/
│   ├── deploy.ps1              # Main PowerShell deployment script
│   ├── deploy.sh               # Bash deployment script
│   ├── destroy.ps1             # Cleanup script
│   ├── scale.ps1               # Scaling operations
│   └── helpers/
│       ├── aks-setup.ps1       # AKS configuration
│       ├── databases.ps1       # Database provisioning
│       └── networking.ps1      # Network setup
├── templates/
│   ├── main.bicep              # Main Bicep template
│   ├── aks.bicep               # AKS module
│   ├── databases.bicep         # Database resources
│   ├── networking.bicep        # VNet and NSG
│   └── monitoring.bicep        # Monitoring stack
└── configs/
    ├── test.env                # Test environment variables
    ├── dev.env                 # Development environment variables
    ├── prod.env                # Production environment variables
    └── helm-values/
        ├── test-values.yaml    # Helm overrides for test
        ├── dev-values.yaml     # Helm overrides for dev
        └── prod-values.yaml    # Helm overrides for prod
```

## Post-Deployment Steps

1. **Get AKS Credentials**
   ```bash
   az aks get-credentials --resource-group openframe-test --name openframe-aks
   ```

2. **Verify Cluster**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

3. **Access Dashboard**
   ```bash
   kubectl port-forward svc/openframe-gateway 8080:8080 -n openframe
   # Access at http://localhost:8080
   ```

4. **Configure DNS** (Production)
   - Point your domain to the Azure Load Balancer IP
   - Configure TLS certificates via cert-manager

## Cost Optimization Tips

1. **Use Azure Spot Instances** for non-critical workloads
2. **Enable cluster autoscaler** to scale down during off-hours
3. **Use Cosmos DB serverless** for test/dev environments
4. **Schedule cluster scale-down** for development environments
5. **Use Reserved Instances** for production (1-3 year commitment = 30-60% savings)

## Scaling Guide

### Scale AKS Nodes
```powershell
./scripts/scale.ps1 -Nodes 5 -ResourceGroup openframe-prod
```

### Upgrade to Production
```powershell
./scripts/deploy.ps1 -Environment prod -ResourceGroup openframe-prod -Location eastus -Upgrade
```

## Troubleshooting

### Common Issues

1. **Insufficient quota**: Request quota increase in Azure Portal
2. **Network connectivity**: Check NSG rules and VNet peering
3. **Pod scheduling failures**: Verify node resources and taints

### Logs and Diagnostics
```bash
# View AKS diagnostics
az aks show --resource-group openframe-test --name openframe-aks

# Check pod logs
kubectl logs -f deployment/openframe-api -n openframe
```

## Security Considerations

- All secrets stored in Azure Key Vault
- Managed identities for service authentication
- Network policies enabled in AKS
- Private endpoints for databases (production)
- TLS encryption for all communications
