@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Name for the Function App plan')
param planName string

@description('Name for the Function App')
param appName string

@description('Name for the user-assigned managed identity')
param identityName string

@description('Resource ID of the subnet for VNet integration')
param subnetId string

@description('Resource ID of the storage account to grant RBAC on')
param storageAccountId string

@description('Name of the storage account (used for AzureWebJobsStorage__accountname)')
param storageAccountName string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Resource ID of the Key Vault for content storage connection string')
param keyVaultId string

@description('Resource ID of the content storage account')
param contentStorageAccountId string

@description('Key Vault reference for content storage connection string')
param contentStorageConnectionStringReference string

@description('Name of the content file share')
param contentShareName string

//
// User-Assigned Managed Identity
//
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
  tags: tags
}

//
// Storage RBAC for this identity
//
var storageRoleIds = [
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
  '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage Account Contributor
]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: last(split(storageAccountId, '/'))
}

resource storageRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in storageRoleIds: {
    scope: storageAccount
    name: guid(identity.id, storageAccountId, roleId)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalType: 'ServicePrincipal'
      principalId: identity.properties.principalId
    }
  }
]

//
// Key Vault RBAC — Key Vault Secrets User for the user-assigned identity
//
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: last(split(keyVaultId, '/'))
}

resource kvRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(identity.id, keyVaultId, '4633458b-17de-408a-b874-0445c86b69e6')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalType: 'ServicePrincipal'
    principalId: identity.properties.principalId
  }
}

//
// Function App Plan (Elastic Premium EP1)
//
resource plan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'elastic'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: 1
  }
  properties: {
    maximumElasticWorkerCount: 20
  }
}

//
// Function App
//
resource app 'Microsoft.Web/sites@2022-09-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: plan.id
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
    virtualNetworkSubnetId: subnetId
    keyVaultReferenceIdentity: identity.id
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
}

resource config 'Microsoft.Web/sites/config@2024-11-01' = {
  name: 'appsettings'
  parent: app
  properties: {
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'node'
    WEBSITE_NODE_DEFAULT_VERSION: '~22'

    // Storage via managed identity
    AzureWebJobsStorage__accountname: storageAccountName

    // storage via user-assigned identity
    AzureWebJobsStorage__credential: 'managedIdentity'
    AzureWebJobsStorage__managedIdentityResourceId: identity.id

    // VNet routing
    WEBSITE_VNET_ROUTE_ALL: '1'
    WEBSITE_CONTENTOVERVNET: '1'

    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'

    // Content file share via Key Vault reference
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: contentStorageConnectionStringReference
    WEBSITE_CONTENTSHARE: contentShareName
  }
}

output name string = app.name
output identityPrincipalId string = identity.properties.principalId
