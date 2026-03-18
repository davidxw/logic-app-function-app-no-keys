@description('The name of the environment, used to generate all resource names')
param environmentName string = 'logicapp-sample'

param location string = resourceGroup().location

param vnetAddressPrefix string = '10.100.0.0/16'
param logicAppSubnetAddressPrefix string = '10.100.0.0/24'
param privateEndpointSubnetAddressPrefix string = '10.100.1.0/24'

var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, location))

// Storage accounts: lowercase alphanumeric only, max 24 chars
var storageAccountName = take(toLower(replace('st${environmentName}${resourceToken}', '-', '')), 24)
var logicAppPlanName = toLower('la-plan-${environmentName}-${resourceToken}')
var logicAppName = toLower('la-${environmentName}-${resourceToken}')
var logicAppIdentityName = toLower('id-la-${environmentName}-${resourceToken}')
var logAnalyticsWorkspaceName = toLower('log-${environmentName}-${resourceToken}')
var applicationInsightsName = toLower('appi-${environmentName}-${resourceToken}')
var vnetName = toLower('vnet-${environmentName}-${resourceToken}')
var logicAppSubnetName = 'snet-logicapp'
var privateEndpointSubnetName = 'snet-pe'
var fileShareName = toLower(logicAppName)
var privateStorageFileDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'
var privateStorageBlobDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var privateStorageQueueDnsZoneName = 'privatelink.queue.${environment().suffixes.storage}'
var privateStorageTableDnsZoneName = 'privatelink.table.${environment().suffixes.storage}'

var tags = {
  SecurityControl: 'Ignore'
  CostControl: 'Ignore'
}

//
// Managed Identity (used by the Logic App to access workflow storage via managed identity)
//
resource logicAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: logicAppIdentityName
  location: location
  tags: tags
}

//
// Storage Account (workflow storage for the Logic App)
//
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// RBAC roles to allow the logic app user-assigned identity to access workflow storage
var storageRoleIds = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
  '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage Account Contributor
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
  '69566ab7-960f-475b-8e7c-b3118f30c6bd' // Storage File Data Privileged Contributor
]

resource storageAccountRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in storageRoleIds: {
    scope: storageAccount
    name: guid(logicApp.id, 'workflowStorage', roleId)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalType: 'ServicePrincipal'
      principalId: logicAppIdentity.properties.principalId
    }
  }
]

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
    ]
  }
}

//
// Storage File Share
//
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: fileShareName
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
var storagePrivateEndpoints = [
  { name: '${storageAccountName}-file-pe', groupId: 'file' }
  { name: '${storageAccountName}-blob-pe', groupId: 'blob' }
  { name: '${storageAccountName}-queue-pe', groupId: 'queue' }
  { name: '${storageAccountName}-table-pe', groupId: 'table' }
]

resource privateEndpoints 'Microsoft.Network/privateEndpoints@2023-04-01' = [
  for pe in storagePrivateEndpoints: {
    name: pe.name
    location: location
    tags: tags
    properties: {
      subnet: {
        id: vnet.properties.subnets[1].id
      }
      privateLinkServiceConnections: [
        {
          name: pe.name
          properties: {
            privateLinkServiceId: storageAccount.id
            groupIds: [
              pe.groupId
            ]
          }
        }
      ]
    }
    dependsOn: [
      fileShare
    ]
  }
]

resource privateDnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = [
  for (pe, i) in storagePrivateEndpoints: {
    parent: privateEndpoints[i]
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

// Monitoring Metrics Publisher role for the Logic App system-assigned identity on App Insights
resource appInsightsRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(logicApp.id, 'appInsights', '3913510d-42f4-4e42-8a64-420c390055eb')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalType: 'ServicePrincipal'
    principalId: logicApp.identity.principalId
  }
}

//
// Logic App Standard
//
resource logicAppPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: logicAppPlanName
  location: location
  tags: tags
  kind: 'elastic'
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
    size: 'WS1'
    family: 'WS'
    capacity: 1
  }
}

resource logicApp 'Microsoft.Web/sites@2022-09-01' = {
  name: logicAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  properties: {
    serverFarmId: logicAppPlan.id
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
    virtualNetworkSubnetId: vnet.properties.subnets[0].id
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${logicAppIdentity.id}': {}
    }
  }
}

resource config 'Microsoft.Web/sites/config@2024-11-01' = {
  name: 'appsettings'
  parent: logicApp
  properties: {
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'node'
    WEBSITE_NODE_DEFAULT_VERSION: '22'

    // Workflow storage via managed identity
    AzureWebJobsStorage__managedIdentityResourceId: logicAppIdentity.id
    AzureWebJobsStorage__credential: 'managedIdentity'
    AzureWebJobsStorage__blobServiceUri: storageAccount.properties.primaryEndpoints.blob
    AzureWebJobsStorage__queueServiceUri: storageAccount.properties.primaryEndpoints.queue
    AzureWebJobsStorage__tableServiceUri: storageAccount.properties.primaryEndpoints.table

    // Content file share
    WEBSITE_CONTENTSHARE: fileShareName
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

    // VNet routing
    WEBSITE_VNET_ROUTE_ALL: '1'
    WEBSITE_CONTENTOVERVNET: '1'

    AzureFunctionsJobHost__extensionBundle__id: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
    AzureFunctionsJobHost__extensionBundle__version: '${'[1.*,'}${' 2.0.0)'}'
    APP_KIND: 'workflowApp'

    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'
    WORKFLOWS_RESOURCE_GROUP_NAME: resourceGroup().name
    WORKFLOWS_SUBSCRIPTION_ID: subscription().subscriptionId
    WORKFLOWS_LOCATION_NAME: location
    WORKFLOWS_TENANT_ID: subscription().tenantId
    WORKFLOWS_MANAGEMENT_BASE_URI: 'https://management.azure.com/'
  }
}

output createdLogicAppName string = logicAppName
