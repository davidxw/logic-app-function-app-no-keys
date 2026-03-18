# Logic App Standard - Azure Deployment

This repo deploys an Azure Logic App Standard instance with all required infrastructure using Azure Developer CLI (`azd`).

## What gets deployed

- **Logic App Standard** (Workflow Standard WS1 plan)
- **Storage Account** (workflow runtime storage)
- **Log Analytics Workspace**
- **Application Insights**
- **User-Assigned Managed Identity**

All connections use **managed identity authentication — no keys or connection strings are required**:

- The Logic App's **workflow storage** (blobs, queues, tables) is accessed via a user-assigned managed identity with the appropriate RBAC roles.
- **Application Insights** is configured with `DisableLocalAuth: true` and uses the Logic App's system-assigned managed identity (Monitoring Metrics Publisher role) for telemetry ingestion.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- An Azure subscription

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

