# Logic App Standard - Azure Deployment

This repo deploys an Azure Logic App Standard instance with all required infrastructure using Azure Developer CLI (`azd`). Alternative you can use the link below:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/[<URL_to_your_raw_bicep_file>](https://github.com/davidxw/logic-app-standard-no-keys/blob/main/infra/main.bicep))


## What gets deployed

- **Logic App Standard** (Workflow Standard WS1 plan) with VNet integration
- **Storage Account** (workflow runtime storage) with public access denied
- **Virtual Network** with two subnets:
  - `snet-logicapp` — delegated to `Microsoft.Web/serverFarms` for Logic App VNet integration
  - `snet-pe` — hosts private endpoints for the storage account
- **Private Endpoints** for storage (file, blob, queue, table)
- **Private DNS Zones** for each storage service (`privatelink.file.*`, `privatelink.blob.*`, `privatelink.queue.*`, `privatelink.table.*`) with VNet links
- **File Share** for Logic App content storage
- **Log Analytics Workspace**
- **Application Insights**
- **User-Assigned Managed Identity**

All connections use **managed identity authentication — no keys or connection strings are required**:

- The Logic App's **workflow storage** (blobs, queues, tables, files) is accessed via a user-assigned managed identity with the appropriate RBAC roles.
- **Application Insights** is configured with `DisableLocalAuth: true` and uses the Logic App's system-assigned managed identity (Monitoring Metrics Publisher role) for telemetry ingestion.
- The **storage account** has public network access denied and is accessible only via private endpoints over the VNet. The Logic App routes all traffic through the VNet (`WEBSITE_VNET_ROUTE_ALL`) and accesses content over the VNet (`WEBSITE_CONTENTOVERVNET`).

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- An Azure subscription

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environmentName` | `logicapp-sample` | Name prefix used to generate all resource names |
| `location` | Resource group location | Azure region for deployment |
| `vnetAddressPrefix` | `10.100.0.0/16` | VNet address space |
| `logicAppSubnetAddressPrefix` | `10.100.0.0/24` | Logic App subnet address range |
| `privateEndpointSubnetAddressPrefix` | `10.100.1.0/24` | Private endpoint subnet address range |

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

