# Logic App Standard & Function App - Keyless Private Storage Deployment

This repo deploys an Azure Logic App Standard and Function App with all required infrastructure using Azure Developer CLI (`azd`). Both apps connect to dedicated storage accounts over private endpoints using managed identity — no keys or SAS tokens for runtime storage. Content file shares use separate storage accounts with connection strings secured in Key Vault.

## What gets deployed

- **Logic App Standard** (Workflow Standard WS1 plan) with VNet integration
- **Function App** (Elastic Premium EP1 plan) with VNet integration
- **Runtime Storage Accounts** (one per app) — used for `AzureWebJobsStorage` (triggers, leases, queues, etc.) with public access disabled and shared key access disabled. Accessed via managed identity.
- **Content Storage Accounts** (one per app) — used for `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` / `WEBSITE_CONTENTSHARE` to store deployed application files on Azure Files. Shared key access is enabled (required by the platform for content shares). Connection strings are stored as Key Vault secrets and referenced via `@Microsoft.KeyVault(...)` syntax.
- **Azure Key Vault** — stores content storage connection strings; public access disabled, accessible via private endpoint only. Both apps are granted the Key Vault Secrets User role.
- **Virtual Network** with three subnets:
  - `snet-logicapp` — delegated to `Microsoft.Web/serverFarms` for Logic App VNet integration
  - `snet-pe` — hosts private endpoints for storage accounts and Key Vault
  - `snet-functionapp` — delegated to `Microsoft.Web/serverFarms` for Function App VNet integration
- **Private Endpoints** for all storage accounts (file, blob, queue, table for runtime; file for content) and Key Vault
- **Private DNS Zones** for each storage service (`privatelink.file.*`, `privatelink.blob.*`, `privatelink.queue.*`, `privatelink.table.*`) and Key Vault (`privatelink.vaultcore.azure.net`) with VNet links
- **Log Analytics Workspace**
- **Application Insights** (shared, with local auth disabled)
- **User-Assigned Managed Identities** — one per app, for independent RBAC tuning

## WebJobsStorage vs Content Storage

The Azure Functions / Logic Apps platform uses two distinct storage concerns:

### AzureWebJobsStorage (runtime storage)

This is the **runtime storage account** used by the Functions host and Logic Apps workflow engine for:
- Trigger management and lease tracking (blob leases, queue polling)
- Durable Functions state (history and instance tables)
- Timer trigger scheduling
- Internal coordination between instances

In this template, each app has a **dedicated runtime storage account** with `allowSharedKeyAccess: false` and `publicNetworkAccess: Disabled`. Access is via **managed identity** using the `AzureWebJobsStorage__credential = managedIdentity` pattern. No connection strings or keys are involved.

### WEBSITE_CONTENTAZUREFILECONNECTIONSTRING / WEBSITE_CONTENTSHARE (content storage)

This is the **content file share** where the platform stores the deployed application code and configuration files for the app. It is an Azure Files share that the platform mounts at runtime.

**Key difference**: The content share connection **requires a storage account connection string with shared key access** — Azure Files do not support managed identity for this setting. To keep keys secure:
1. Each app has a **separate content storage account** with `allowSharedKeyAccess: true`
2. The connection string (containing the account key) is stored as a **Key Vault secret**
3. The app setting uses a **Key Vault reference** (`@Microsoft.KeyVault(SecretUri=...)`) so the key never appears in app configuration directly
4. The content storage accounts are accessible only via **private endpoints**

## Key settings for private storage with managed identity (no keys)

The following settings are required on the **Logic App** and **Function App** to connect to a storage account that has `allowSharedKeyAccess: false` and is accessible only via private endpoints.

### Storage account configuration

**Runtime storage accounts** (one per app):

| Setting | Value | Purpose |
|---------|-------|---------|
| `allowSharedKeyAccess` | `false` | Disables shared key and SAS token access |
| `publicNetworkAccess` | `Disabled` | Disables the public endpoint entirely |
| `networkAcls.defaultAction` | `Deny` | Blocks public network access to the storage account |

**Content storage accounts** (one per app):

| Setting | Value | Purpose |
|---------|-------|---------|
| `allowSharedKeyAccess` | `true` | Required — the platform needs a connection string for content shares |
| `publicNetworkAccess` | `Disabled` | Disables the public endpoint entirely |
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
| `WEBSITE_VNET_ROUTE_ALL` | `1` | Yes | Yes | Route all outbound traffic through the VNet, include WebJobStorage account |
| `WEBSITE_CONTENTOVERVNET` | `1` | Yes | Yes | Access content file share via private endpoint |

### App settings — Content file share (Key Vault backed)

| App Setting | Value | Logic App | Function App | Purpose |
|-------------|-------|:---------:|:------------:|---------|
| `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` | `@Microsoft.KeyVault(SecretUri=...)` | Yes | Yes | Key Vault reference to the content storage account connection string |
| `WEBSITE_CONTENTSHARE` | File share name | Yes | Yes | Name of the Azure Files share for deployed app content |

Each app has a dedicated content storage account. The connection string (which includes the account key) is stored in Key Vault and referenced using the `@Microsoft.KeyVault(SecretUri=<uri>)` syntax, so the key is never exposed in app settings directly.

### Key Vault RBAC

| Role | Role ID | Purpose |
|------|---------|---------|
| Key Vault Secrets User | `4633458b-17de-408a-b874-0445c86b69e6` | Allows the app's system-assigned identity to read Key Vault secrets for Key Vault references |

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

