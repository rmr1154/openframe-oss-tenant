// OpenFrame Azure Infrastructure
// Main Bicep template for deploying all resources

@description('Environment name (test, dev, prod)')
@allowed(['test', 'dev', 'prod'])
param environment string = 'test'

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'openframe'

// Environment-specific configurations
var envConfig = {
  test: {
    aksNodeCount: 1
    aksNodeSize: 'Standard_B4ms'
    aksMinNodes: 1
    aksMaxNodes: 2
    cosmosServerless: true
    cosmosRU: 0
    redisSku: 'Basic'
    redisSize: 'C0'
    eventHubsSku: 'Basic'
    eventHubsCapacity: 1
    acrSku: 'Basic'
    enableMonitoring: false
  }
  dev: {
    aksNodeCount: 2
    aksNodeSize: 'Standard_B4ms'
    aksMinNodes: 2
    aksMaxNodes: 4
    cosmosServerless: false
    cosmosRU: 1000
    redisSku: 'Standard'
    redisSize: 'C1'
    eventHubsSku: 'Standard'
    eventHubsCapacity: 1
    acrSku: 'Standard'
    enableMonitoring: true
  }
  prod: {
    aksNodeCount: 3
    aksNodeSize: 'Standard_D4s_v5'
    aksMinNodes: 3
    aksMaxNodes: 10
    cosmosServerless: false
    cosmosRU: 4000
    redisSku: 'Premium'
    redisSize: 'P1'
    eventHubsSku: 'Standard'
    eventHubsCapacity: 2
    acrSku: 'Standard'
    enableMonitoring: true
  }
}

var config = envConfig[environment]
var namingPrefix = 'of-${environment}'
var uniqueSuffix = uniqueString(resourceGroup().id)

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: '${namingPrefix}-vnet'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.0.0.0/22'
        }
      }
      {
        name: 'db-subnet'
        properties: {
          addressPrefix: '10.0.4.0/24'
        }
      }
    ]
  }
}

// Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: '${baseName}${environment}acr${uniqueSuffix}'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  sku: {
    name: config.acrSku
  }
  properties: {
    adminUserEnabled: false
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${namingPrefix}-kv-${uniqueSuffix}'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// AKS Cluster
resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: '${namingPrefix}-aks'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${namingPrefix}-aks'
    kubernetesVersion: '1.29'
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.0.8.0/24'
      dnsServiceIP: '10.0.8.10'
    }
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: config.aksNodeCount
        vmSize: config.aksNodeSize
        mode: 'System'
        enableAutoScaling: true
        minCount: config.aksMinNodes
        maxCount: config.aksMaxNodes
        vnetSubnetID: vnet.properties.subnets[0].id
        osType: 'Linux'
      }
    ]
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
        }
      }
      omsAgent: {
        enabled: config.enableMonitoring
        config: config.enableMonitoring ? {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        } : {}
      }
    }
  }
}

// Role assignment for AKS to pull from ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, 'acrpull')
  scope: acr
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalType: 'ServicePrincipal'
  }
}

// Log Analytics Workspace (for monitoring)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (config.enableMonitoring) {
  name: '${namingPrefix}-logs'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Cosmos DB (MongoDB API)
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: '${namingPrefix}-cosmos-${uniqueSuffix}'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: environment == 'prod'
      }
    ]
    capabilities: config.cosmosServerless ? [
      { name: 'EnableServerless' }
      { name: 'EnableMongo' }
    ] : [
      { name: 'EnableMongo' }
    ]
    apiProperties: {
      serverVersion: '7.0'
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases@2023-11-15' = {
  parent: cosmosAccount
  name: 'openframe'
  properties: {
    resource: {
      id: 'openframe'
    }
  }
}

// Azure Cache for Redis
resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: '${namingPrefix}-redis-${uniqueSuffix}'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  properties: {
    sku: {
      name: config.redisSku
      family: config.redisSku == 'Premium' ? 'P' : 'C'
      capacity: config.redisSku == 'Premium' ? 1 : (config.redisSize == 'C0' ? 0 : 1)
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
  }
}

// Event Hubs Namespace
resource eventHubsNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: '${namingPrefix}-eventhubs-${uniqueSuffix}'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  sku: {
    name: config.eventHubsSku
    tier: config.eventHubsSku
    capacity: config.eventHubsCapacity
  }
  properties: {
    kafkaEnabled: true
  }
}

// Event Hubs (Kafka topics)
var eventHubTopics = ['pinot-events', 'devices-topic', 'integrated-tool-events', 'fleet-activities']

resource eventHubs 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = [for topic in eventHubTopics: {
  parent: eventHubsNamespace
  name: topic
  properties: {
    partitionCount: environment == 'prod' ? 8 : 2
    messageRetentionInDays: environment == 'prod' ? 7 : 1
  }
}]

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${baseName}${environment}${uniqueSuffix}'
  location: location
  tags: {
    Environment: environment
    Project: 'OpenFrame'
  }
  sku: {
    name: environment == 'prod' ? 'Standard_ZRS' : 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Outputs
output aksName string = aks.name
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = keyVault.name
output cosmosDbName string = cosmosAccount.name
output cosmosDbConnectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
output redisHostName string = redis.properties.hostName
output eventHubsNamespaceName string = eventHubsNamespace.name
output storageAccountName string = storageAccount.name
output vnetId string = vnet.id
