@description('The name of the environment, used to generate all resource names')
param environmentName string

param location string = resourceGroup().location

param vnetAddressPrefix string = '10.100.0.0/16'
param logicAppSubnetAddressPrefix string = '10.100.0.0/24'
param privateEndpointSubnetAddressPrefix string = '10.100.1.0/24'
param functionAppSubnetAddressPrefix string = '10.100.2.0/24'

var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, location))

// Storage accounts: lowercase alphanumeric only, max 24 chars
var laStorageAccountName = take(toLower(replace('stla${environmentName}${resourceToken}', '-', '')), 24)
var funcStorageAccountName = take(toLower(replace('stfn${environmentName}${resourceToken}', '-', '')), 24)
var laContentStorageAccountName = take(toLower(replace('stlac${environmentName}${resourceToken}', '-', '')), 24)
var funcContentStorageAccountName = take(toLower(replace('stfnc${environmentName}${resourceToken}', '-', '')), 24)
var laContentShareName = 'la-content'
var funcContentShareName = 'func-content'
var keyVaultName = take(toLower(replace('kv-${environmentName}-${resourceToken}', '-', '')), 24)
var logicAppPlanName = toLower('la-plan-${environmentName}-${resourceToken}')
var logicAppName = toLower('la-${environmentName}-${resourceToken}')
var functionAppPlanName = toLower('func-plan-${environmentName}-${resourceToken}')
var functionAppName = toLower('func-${environmentName}-${resourceToken}')
var logicAppIdentityName = toLower('id-la-${environmentName}-${resourceToken}')
var functionAppIdentityName = toLower('id-func-${environmentName}-${resourceToken}')
var logAnalyticsWorkspaceName = toLower('log-${environmentName}-${resourceToken}')
var applicationInsightsName = toLower('appi-${environmentName}-${resourceToken}')
var vnetName = toLower('vnet-${environmentName}-${resourceToken}')
var logicAppSubnetName = 'snet-logicapp'
var functionAppSubnetName = 'snet-functionapp'
var privateEndpointSubnetName = 'snet-pe'

var privateStorageFileDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'
var privateStorageBlobDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var privateStorageQueueDnsZoneName = 'privatelink.queue.${environment().suffixes.storage}'
var privateStorageTableDnsZoneName = 'privatelink.table.${environment().suffixes.storage}'
var privateKeyVaultDnsZoneName = 'privatelink.vaultcore.azure.net'

var tags = {
}

//
// Web Job Storage Account for Logic App
//
resource laStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: laStorageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

//
// Web Job Storage Account for Function App
//
resource funcStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: funcStorageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

//
// Content Storage Account for Logic App (file shares, keys enabled)
//
resource laContentStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: laContentStorageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource laContentFileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: laContentStorageAccount
  name: 'default'
}

resource laContentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: laContentFileService
  name: laContentShareName
}

//
// Content Storage Account for Function App (file shares, keys enabled)
//
resource funcContentStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: funcContentStorageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource funcContentFileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: funcContentStorageAccount
  name: 'default'
}

resource funcContentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: funcContentFileService
  name: funcContentShareName
}

//
// Virtual Network
//
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: logicAppSubnetName
        properties: {
          addressPrefix: logicAppSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'webapp'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          privateLinkServiceNetworkPolicies: 'Enabled'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: functionAppSubnetName
        properties: {
          addressPrefix: functionAppSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'webapp'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

//
// Private DNS Zones for Storage
//
var storageDnsZoneNames = [
  privateStorageFileDnsZoneName
  privateStorageBlobDnsZoneName
  privateStorageQueueDnsZoneName
  privateStorageTableDnsZoneName
]

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for zoneName in storageDnsZoneNames: {
    name: zoneName
    location: 'global'
  }
]

resource privateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zoneName, i) in storageDnsZoneNames: {
    parent: privateDnsZones[i]
    name: '${zoneName}-link'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

//
// Private Endpoints for Storage
//
var storageGroupIds = ['file', 'blob', 'queue', 'table']

// Private Endpoints for Logic App Storage
resource laPrivateEndpoints 'Microsoft.Network/privateEndpoints@2023-04-01' = [
  for groupId in storageGroupIds: {
    name: '${laStorageAccountName}-${groupId}-pe'
    location: location
    tags: tags
    properties: {
      subnet: {
        id: vnet.properties.subnets[1].id
      }
      privateLinkServiceConnections: [
        {
          name: '${laStorageAccountName}-${groupId}-pe'
          properties: {
            privateLinkServiceId: laStorageAccount.id
            groupIds: [
              groupId
            ]
          }
        }
      ]
    }
  }
]

resource laPrivateDnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = [
  for (groupId, i) in storageGroupIds: {
    parent: laPrivateEndpoints[i]
    name: 'default'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config1'
          properties: {
            privateDnsZoneId: privateDnsZones[i].id
          }
        }
      ]
    }
  }
]

// Private Endpoints for Function App Storage
resource funcPrivateEndpoints 'Microsoft.Network/privateEndpoints@2023-04-01' = [
  for groupId in storageGroupIds: {
    name: '${funcStorageAccountName}-${groupId}-pe'
    location: location
    tags: tags
    properties: {
      subnet: {
        id: vnet.properties.subnets[1].id
      }
      privateLinkServiceConnections: [
        {
          name: '${funcStorageAccountName}-${groupId}-pe'
          properties: {
            privateLinkServiceId: funcStorageAccount.id
            groupIds: [
              groupId
            ]
          }
        }
      ]
    }
  }
]

resource funcPrivateDnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = [
  for (groupId, i) in storageGroupIds: {
    parent: funcPrivateEndpoints[i]
    name: 'default'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config1'
          properties: {
            privateDnsZoneId: privateDnsZones[i].id
          }
        }
      ]
    }
  }
]

//
// Private DNS Zone for Key Vault
//
resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateKeyVaultDnsZoneName
  location: 'global'
}

resource keyVaultDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: '${privateKeyVaultDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

//
// Private Endpoints for Content Storage Accounts (file only)
//
resource laContentPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: '${laContentStorageAccountName}-file-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${laContentStorageAccountName}-file-pe'
        properties: {
          privateLinkServiceId: laContentStorageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

resource laContentPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: laContentPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZones[0].id // file DNS zone
        }
      }
    ]
  }
}

resource funcContentPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: '${funcContentStorageAccountName}-file-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${funcContentStorageAccountName}-file-pe'
        properties: {
          privateLinkServiceId: funcContentStorageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

resource funcContentPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: funcContentPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZones[0].id // file DNS zone
        }
      }
    ]
  }
}

//
// Key Vault
//
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Disabled'
    enableSoftDelete: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: '${keyVaultName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVaultName}-pe'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: keyVaultDnsZone.id
        }
      }
    ]
  }
}

//
// Key Vault Secrets — content storage connection strings
//
resource laContentConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'la-content-storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${laContentStorageAccount.name};AccountKey=${laContentStorageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}

resource funcContentConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'func-content-storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${funcContentStorageAccount.name};AccountKey=${funcContentStorageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}

//
// Log Analytics & Application Insights
//
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    DisableLocalAuth: true
  }
}

// Monitoring Metrics Publisher role for app user-assigned identities on App Insights
resource appInsightsRbacLogicApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(logicAppIdentityName, 'appInsights', '3913510d-42f4-4e42-8a64-420c390055eb')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalType: 'ServicePrincipal'
    principalId: logicApp.outputs.identityPrincipalId
  }
}

resource appInsightsRbacFunctionApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(functionAppIdentityName, 'appInsights', '3913510d-42f4-4e42-8a64-420c390055eb')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalType: 'ServicePrincipal'
    principalId: functionApp.outputs.identityPrincipalId
  }
}

//
// Logic App Standard (module)
//
module logicApp 'modules/logicapp.bicep' = {
  name: 'logicApp'
  params: {
    location: location
    tags: tags
    planName: logicAppPlanName
    appName: logicAppName
    identityName: logicAppIdentityName
    subnetId: vnet.properties.subnets[0].id
    storageAccountId: laStorageAccount.id
    storageBlobEndpoint: laStorageAccount.properties.primaryEndpoints.blob
    storageQueueEndpoint: laStorageAccount.properties.primaryEndpoints.queue
    storageTableEndpoint: laStorageAccount.properties.primaryEndpoints.table
    appInsightsConnectionString: applicationInsights.properties.ConnectionString
    keyVaultId: keyVault.id
    contentStorageAccountId: laContentStorageAccount.id
    contentStorageConnectionStringReference: '@Microsoft.KeyVault(SecretUri=${laContentConnectionStringSecret.properties.secretUri})'
    contentShareName: laContentShareName
  }
  dependsOn: [
    laPrivateDnsZoneGroups
    laContentPrivateDnsZoneGroup
    keyVaultPrivateDnsZoneGroup
  ]
}

//
// Function App (module)
//
module functionApp 'modules/functionapp.bicep' = {
  name: 'functionApp'
  params: {
    location: location
    tags: tags
    planName: functionAppPlanName
    appName: functionAppName
    identityName: functionAppIdentityName
    subnetId: vnet.properties.subnets[2].id
    storageAccountId: funcStorageAccount.id
    storageAccountName: funcStorageAccount.name
    appInsightsConnectionString: applicationInsights.properties.ConnectionString
    keyVaultId: keyVault.id
    contentStorageAccountId: funcContentStorageAccount.id
    contentStorageConnectionStringReference: '@Microsoft.KeyVault(SecretUri=${funcContentConnectionStringSecret.properties.secretUri})'
    contentShareName: funcContentShareName
  }
  dependsOn: [
    funcPrivateDnsZoneGroups
    funcContentPrivateDnsZoneGroup
    keyVaultPrivateDnsZoneGroup
  ]
}

output createdLogicAppName string = logicApp.outputs.name
output createdFunctionAppName string = functionApp.outputs.name
