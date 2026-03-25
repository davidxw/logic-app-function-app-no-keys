@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Name for the Logic App plan')
param planName string

@description('Name for the Logic App')
param appName string

@description('Name for the user-assigned managed identity')
param identityName string

@description('Resource ID of the subnet for VNet integration')
param subnetId string

@description('Resource ID of the storage account to grant RBAC on')
param storageAccountId string

@description('Blob service endpoint of the storage account')
param storageBlobEndpoint string

@description('Queue service endpoint of the storage account')
param storageQueueEndpoint string

@description('Table service endpoint of the storage account')
param storageTableEndpoint string

@description('Application Insights connection string')
param appInsightsConnectionString string

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
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
  '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage Account Contributor
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
  '69566ab7-960f-475b-8e7c-b3118f30c6bd' // Storage File Data Privileged Contributor
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
// Logic App Plan (Workflow Standard WS1)
//
resource plan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planName
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

//
// Logic App Standard
//
resource app 'Microsoft.Web/sites@2022-09-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  properties: {
    serverFarmId: plan.id
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
    virtualNetworkSubnetId: subnetId
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
    WEBSITE_NODE_DEFAULT_VERSION: '22'

    // Workflow storage via managed identity

    AzureWebJobsStorage__blobServiceUri: storageBlobEndpoint
    AzureWebJobsStorage__queueServiceUri: storageQueueEndpoint
    AzureWebJobsStorage__tableServiceUri: storageTableEndpoint

    // storage via user-assigned identity
    AzureWebJobsStorage__managedIdentityResourceId: identity.id
    AzureWebJobsStorage__credential: 'managedIdentity'
    
    // VNet routing
    WEBSITE_VNET_ROUTE_ALL: '1'
    WEBSITE_CONTENTOVERVNET: '1'

    AzureFunctionsJobHost__extensionBundle__id: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
    AzureFunctionsJobHost__extensionBundle__version: '${'[1.*,'}${' 2.0.0)'}'
    APP_KIND: 'workflowApp'

    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'
    WORKFLOWS_RESOURCE_GROUP_NAME: resourceGroup().name
    WORKFLOWS_SUBSCRIPTION_ID: subscription().subscriptionId
    WORKFLOWS_LOCATION_NAME: location
    WORKFLOWS_TENANT_ID: subscription().tenantId
    WORKFLOWS_MANAGEMENT_BASE_URI: 'https://management.azure.com/'
  }
}

output name string = app.name
output principalId string = app.identity.principalId
