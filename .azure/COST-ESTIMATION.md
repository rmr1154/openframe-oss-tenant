# OpenFrame Azure Cost Estimation

This document provides detailed cost estimates for deploying OpenFrame on Azure across different environments. Prices are based on East US region (February 2026) and may vary by region and over time.

## Cost Summary

| Environment | Monthly Cost | Annual Cost | Use Case |
|------------|-------------|-------------|----------|
| **Test** | $150 - $250 | $1,800 - $3,000 | Evaluation, demos, CI/CD |
| **Development** | $350 - $500 | $4,200 - $6,000 | Active development, staging |
| **Production** | $1,500 - $3,000 | $18,000 - $36,000 | Live workloads, enterprise |

---

## Test Environment (Minimal Cost)

Designed for evaluation, quick demos, and CI/CD testing.

### Compute Resources

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **AKS Cluster** | 1x Standard_B4ms (4 vCPU, 16GB) | ~$85 |
| **AKS Management** | Free tier | $0 |

### Data Services

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **Cosmos DB** | Serverless (MongoDB API) | ~$25-50* |
| **Azure Cache for Redis** | Basic C0 (250MB) | ~$16 |
| **Event Hubs** | Basic tier, 1 TU | ~$11 |

*Cosmos DB Serverless costs depend on actual usage (RUs consumed)

### Storage & Networking

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **Storage Account** | Standard LRS, 50GB | ~$1 |
| **Container Registry** | Basic SKU | ~$5 |
| **Load Balancer** | Basic | ~$18 |
| **Bandwidth** | 10GB egress | ~$1 |

### Total Test Environment: **~$162-206/month**

#### Cost Optimization Tips for Test:
- Schedule cluster shutdown during off-hours (saves ~60%)
- Use Cosmos DB serverless for pay-per-use pricing
- Delete resources when not in active use

---

## Development Environment

Balanced configuration for active development teams.

### Compute Resources

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **AKS Cluster** | 2x Standard_B4ms (4 vCPU, 16GB each) | ~$170 |
| **AKS Management** | Free tier | $0 |

### Data Services

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **Cosmos DB** | Provisioned 1000 RU/s | ~$58 |
| **Azure Cache for Redis** | Standard C1 (1GB) | ~$41 |
| **Event Hubs** | Standard tier, 1 TU | ~$22 |

### Storage & Networking

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **Storage Account** | Standard LRS, 100GB | ~$2 |
| **Container Registry** | Standard SKU | ~$20 |
| **Load Balancer** | Standard | ~$18 |
| **Bandwidth** | 50GB egress | ~$4 |
| **Azure Monitor** | Basic (5GB logs) | ~$12 |

### Self-Managed Components (on AKS)

| Component | Resources | Included in AKS |
|-----------|-----------|-----------------|
| Cassandra | 1 replica, 20GB storage | Included |
| Pinot | Controller + Broker + Server | Included |
| ZooKeeper | 1 replica | Included |
| NATS | 1 replica, 5GB storage | Included |
| Prometheus + Grafana | Minimal resources | Included |

### Total Development Environment: **~$347-400/month**

#### Cost Optimization Tips for Dev:
- Use cluster autoscaler to scale down during low usage
- Set up scheduled scaling for non-business hours
- Use Azure Dev/Test subscription pricing (up to 40% savings)

---

## Production Environment

Enterprise-grade configuration with high availability.

### Compute Resources

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **AKS Cluster** | 3x Standard_D4s_v5 (4 vCPU, 16GB each) | ~$420 |
| **AKS Autoscaling** | Up to 10 nodes | Variable |
| **AKS Management** | Standard tier (SLA) | ~$73 |

### Data Services

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **Cosmos DB** | Autoscale 4000-10000 RU/s | ~$230-580 |
| **Azure Cache for Redis** | Premium P1 (6GB, HA) | ~$250 |
| **Event Hubs** | Standard tier, 2 TUs | ~$44 |

### Storage & Networking

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **Storage Account** | Standard ZRS, 500GB | ~$12 |
| **Container Registry** | Standard SKU | ~$20 |
| **Load Balancer** | Standard | ~$18 |
| **Bandwidth** | 500GB egress | ~$40 |
| **Azure Monitor** | Full stack (50GB logs) | ~$115 |
| **Key Vault** | Standard (10K operations) | ~$3 |

### Self-Managed Components (on AKS)

| Component | Configuration | Included in AKS |
|-----------|---------------|-----------------|
| Cassandra | 3 replicas, 100GB each | Included |
| Pinot | 2 Controllers, 2 Brokers, 3 Servers | Included |
| ZooKeeper | 3 replicas | Included |
| NATS | 3 replicas, 20GB storage | Included |
| Prometheus | 50GB retention | Included |
| Grafana + Loki | Full monitoring stack | Included |

### Integrated Tools (if enabled)

| Tool | Additional Cost |
|------|----------------|
| Tactical RMM | ~$50/month (databases) |
| MeshCentral | ~$30/month (databases) |
| Fleet MDM | ~$40/month (databases) |
| Authentik | ~$30/month (databases) |

### Total Production Environment: **~$1,225-1,735/month** (base)
### With Integrated Tools: **~$1,375-1,885/month**
### With Autoscaling Peak: **~$1,800-3,000/month**

---

## Detailed Resource Pricing Reference

### AKS Node Sizes

| VM Size | vCPU | Memory | Pay-As-You-Go | 1-Year Reserved | 3-Year Reserved |
|---------|------|--------|---------------|-----------------|-----------------|
| Standard_B4ms | 4 | 16GB | $85/month | $53/month (38%) | $34/month (60%) |
| Standard_D4s_v5 | 4 | 16GB | $140/month | $89/month (36%) | $57/month (59%) |
| Standard_D8s_v5 | 8 | 32GB | $280/month | $178/month (36%) | $114/month (59%) |

### Cosmos DB (MongoDB API)

| Mode | Configuration | Monthly Cost |
|------|--------------|--------------|
| Serverless | Pay per RU | ~$0.25/million RUs |
| Provisioned | 400 RU/s (min) | ~$23/month |
| Provisioned | 1000 RU/s | ~$58/month |
| Autoscale | 4000 RU/s max | ~$230/month (avg) |

### Azure Cache for Redis

| Tier | Size | Monthly Cost | Features |
|------|------|--------------|----------|
| Basic C0 | 250MB | $16 | No SLA, no replication |
| Standard C1 | 1GB | $41 | SLA, replication |
| Premium P1 | 6GB | $250 | Clustering, persistence |

### Event Hubs (Kafka-compatible)

| Tier | Throughput Units | Monthly Cost | Notes |
|------|------------------|--------------|-------|
| Basic | 1 TU | $11 | 1 consumer group |
| Standard | 1 TU | $22 | 20 consumer groups |
| Standard | 2 TUs | $44 | Higher throughput |

---

## Cost Optimization Strategies

### 1. Reserved Instances (30-60% savings)
- 1-year commitment: ~36% savings
- 3-year commitment: ~59% savings
- Applies to: AKS nodes, Redis, Cosmos DB

### 2. Azure Spot Instances (up to 90% savings)
- For non-critical workloads
- Can be evicted with 30s notice
- Add spot node pools for batch processing

### 3. Scheduled Scaling
```powershell
# Scale down dev cluster after hours
az aks nodepool scale --resource-group openframe-dev `
    --cluster-name of-dev-aks --name nodepool1 --node-count 0

# Scale up before business hours
az aks nodepool scale --resource-group openframe-dev `
    --cluster-name of-dev-aks --name nodepool1 --node-count 2
```

### 4. Azure Dev/Test Subscription
- Up to 40% discount on many services
- No production SLAs
- Great for development environments

### 5. Right-Sizing
- Monitor actual resource usage
- Downsize underutilized resources
- Use Azure Advisor recommendations

### 6. Resource Cleanup
- Set up auto-shutdown for dev resources
- Delete unused resources
- Use Azure Cost Management alerts

---

## Monthly Cost Comparison: Azure vs Self-Hosted

| Component | Azure Managed | Self-Hosted (on AKS) |
|-----------|--------------|---------------------|
| MongoDB | Cosmos DB: $58-580 | 3-node cluster: $0 (compute included) |
| Redis | Cache for Redis: $16-250 | Self-managed: $0 (compute included) |
| Kafka | Event Hubs: $11-44 | Self-managed: $0 (compute included) |
| **Management Overhead** | Low | High |
| **SLA** | 99.95-99.99% | Depends on setup |

**Recommendation:**
- **Test/Dev**: Use Azure managed services for simplicity
- **Production**: Consider hybrid approach
  - Cosmos DB for MongoDB (managed)
  - Self-hosted Kafka/Cassandra (cost savings)
  - Azure Redis for caching (performance)

---

## Break-Even Analysis

### When to Use Reserved Instances

| Monthly Usage | Break-Even Point |
|--------------|------------------|
| < 8 hours/day | Pay-As-You-Go |
| 8-16 hours/day | Consider 1-year RI |
| > 16 hours/day | 1-year or 3-year RI |
| 24/7 production | 3-year RI |

### Cost Calculator Links

- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [Azure Cost Management](https://azure.microsoft.com/services/cost-management/)
- [Azure Advisor](https://azure.microsoft.com/services/advisor/)

---

## Notes

1. All prices are estimates based on East US region
2. Actual costs may vary based on usage patterns
3. Egress bandwidth costs can vary significantly
4. Consider Azure Hybrid Benefit if you have existing licenses
5. Monitor costs regularly using Azure Cost Management
