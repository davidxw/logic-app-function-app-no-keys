# Logic App Standard & Function App - Keyless Private Storage Deployment

This repo deploys an Azure Logic App Standard and Function App with all required infrastructure using Azure Developer CLI (`azd`). Both apps connect to a shared storage account over private endpoints using managed identity — no keys or SAS tokens.

## What gets deployed

- **Logic App Standard** (Workflow Standard WS1 plan) with VNet integration
- **Function App** (Elastic Premium EP1 plan) with VNet integration
- **Storage Account** (shared workflow/runtime storage) with public access denied and shared key access disabled
- **Virtual Network** with three subnets:
  - `snet-logicapp` — delegated to `Microsoft.Web/serverFarms` for Logic App VNet integration
  - `snet-pe` — hosts private endpoints for the storage account
  - `snet-functionapp` — delegated to `Microsoft.Web/serverFarms` for Function App VNet integration
- **Private Endpoints** for storage (file, blob, queue, table)
- **Private DNS Zones** for each storage service (`privatelink.file.*`, `privatelink.blob.*`, `privatelink.queue.*`, `privatelink.table.*`) with VNet links
- **Log Analytics Workspace**
- **Application Insights** (shared, with local auth disabled)
- **User-Assigned Managed Identities** — one per app, for independent RBAC tuning

## Key settings for private storage with managed identity (no keys)

The following settings are required on the **Logic App** and **Function App** to connect to a storage account that has `allowSharedKeyAccess: false` and is accessible only via private endpoints.

### Storage account configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| `allowSharedKeyAccess` | `false` | Disables shared key and SAS token access |
| `networkAcls.defaultAction` | `Deny` | Blocks public network access to the storage account |

### App settings — managed identity storage connection

These settings replace the `AzureWebJobsStorage` connection string with managed identity authentication. The Logic App and Function App use different configuration approaches.

**Logic App** — uses per-service endpoint URIs:

| App Setting | Value |
|-------------|-------|
| `AzureWebJobsStorage__credential` | `managedIdentity` |
| `AzureWebJobsStorage__managedIdentityResourceId` | User-assigned identity resource ID |
| `AzureWebJobsStorage__blobServiceUri` | `https://<account>.blob.core.windows.net` |
| `AzureWebJobsStorage__queueServiceUri` | `https://<account>.queue.core.windows.net` |
| `AzureWebJobsStorage__tableServiceUri` | `https://<account>.table.core.windows.net` |

**Function App** — uses the storage account name (the SDK resolves endpoints automatically):

| App Setting | Value |
|-------------|-------|
| `AzureWebJobsStorage__accountname` | Storage account name |
| `AzureWebJobsStorage__credential` | `managedIdentity` |
| `AzureWebJobsStorage__managedIdentityResourceId` | User-assigned identity resource ID |

### App settings — VNet routing

| App Setting | Value | Logic App | Function App | Purpose |
|-------------|-------|:---------:|:------------:|---------|
| `WEBSITE_VNET_ROUTE_ALL` | `1` | Yes | Yes | Route all outbound traffic through the VNet |
| `WEBSITE_CONTENTOVERVNET` | `1` | Yes | Yes | Access content file share via private endpoint |

### App settings — Application Insights (keyless)

| App Setting | Value | Logic App | Function App | Purpose |
|-------------|-------|:---------:|:------------:|---------|
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Connection string | Yes | Yes | App Insights telemetry endpoint |
| `APPLICATIONINSIGHTS_AUTHENTICATION_STRING` | `Authorization=AAD` | Yes | Yes | Use Entra ID auth instead of instrumentation key |

The Application Insights resource itself is configured with `DisableLocalAuth: true` to enforce Entra ID authentication. Each app's **system-assigned managed identity** is granted the **Monitoring Metrics Publisher** role on Application Insights.

### RBAC roles on the storage account

Each app has its own **user-assigned managed identity** with independent role assignments, allowing per-app tuning.

**Logic App** identity roles:

| Role | Role ID | Purpose |
|------|---------|---------|  
| Storage Blob Data Owner | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` | Read/write blob data |
| Storage Account Contributor | `17d1049b-9a84-46fb-8f53-869881c3d3ab` | Manage the storage account |
| Storage Queue Data Contributor | `974c5e8b-45b9-4653-ba55-5f855dd0fb88` | Read/write queue messages |
| Storage Table Data Contributor | `0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3` | Read/write table entities |
| Storage File Data Privileged Contributor | `69566ab7-960f-475b-8e7c-b3118f30c6bd` | Read/write file share data |

**Function App** identity roles:

| Role | Role ID | Purpose |
|------|---------|---------|  
| Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Read/write blob data |
| Storage Queue Data Contributor | `974c5e8b-45b9-4653-ba55-5f855dd0fb88` | Read/write queue messages |
| Storage Account Contributor | `17d1049b-9a84-46fb-8f53-869881c3d3ab` | Manage the storage account |

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- An Azure subscription

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environmentName` | *(required)* | Name prefix used to generate all resource names |
| `location` | Resource group location | Azure region for deployment |
| `vnetAddressPrefix` | `10.100.0.0/16` | VNet address space |
| `logicAppSubnetAddressPrefix` | `10.100.0.0/24` | Logic App subnet address range |
| `privateEndpointSubnetAddressPrefix` | `10.100.1.0/24` | Private endpoint subnet address range |
| `functionAppSubnetAddressPrefix` | `10.100.2.0/24` | Function App subnet address range |

## Deploy

```bash
azd auth login
azd up
```

You will be prompted to select a subscription and location. The infrastructure will be provisioned automatically.

## Clean up

```bash
azd down
```

