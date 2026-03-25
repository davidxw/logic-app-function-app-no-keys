@description('The name of the environment, used to generate all resource names')
param environmentName string

param location string = resourceGroup().location

param vnetAddressPrefix string = '10.100.0.0/16'
param logicAppSubnetAddressPrefix string = '10.100.0.0/24'
param privateEndpointSubnetAddressPrefix string = '10.100.1.0/24'
param functionAppSubnetAddressPrefix string = '10.100.2.0/24'

var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, location))

// Storage accounts: lowercase alphanumeric only, max 24 chars
var storageAccountName = take(toLower(replace('st${environmentName}${resourceToken}', '-', '')), 24)
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

var tags = {
}

//
// Storage Account (shared runtime storage for Logic App and Function App)
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
    allowSharedKeyAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
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

// Monitoring Metrics Publisher role for app system-assigned identities on App Insights
resource appInsightsRbacLogicApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(logicAppName, 'appInsights', '3913510d-42f4-4e42-8a64-420c390055eb')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalType: 'ServicePrincipal'
    principalId: logicApp.outputs.principalId
  }
}

resource appInsightsRbacFunctionApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(functionAppName, 'appInsights', '3913510d-42f4-4e42-8a64-420c390055eb')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalType: 'ServicePrincipal'
    principalId: functionApp.outputs.principalId
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
    storageAccountId: storageAccount.id
    storageBlobEndpoint: storageAccount.properties.primaryEndpoints.blob
    storageQueueEndpoint: storageAccount.properties.primaryEndpoints.queue
    storageTableEndpoint: storageAccount.properties.primaryEndpoints.table
    appInsightsConnectionString: applicationInsights.properties.ConnectionString
  }
  dependsOn: [
    privateDnsZoneGroups
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
    storageAccountId: storageAccount.id
    storageAccountName: storageAccount.name
    appInsightsConnectionString: applicationInsights.properties.ConnectionString
  }
  dependsOn: [
    privateDnsZoneGroups
  ]
}

output createdLogicAppName string = logicApp.outputs.name
output createdFunctionAppName string = functionApp.outputs.name
