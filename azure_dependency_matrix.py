import json
import pandas as pd

# Load resources.json (exported using az resource list --output json > resources.json)
with open('resources.json', 'r') as f:
    resources = json.load(f)

data = []

# Helper functions
def get_category(resource_type):
    if "Microsoft.Compute" in resource_type:
        return "Compute"
    elif "Microsoft.Web" in resource_type:
        return "App Services"
    elif "Microsoft.Sql" in resource_type:
        return "Database"
    elif "Microsoft.Network" in resource_type:
        return "Networking"
    elif "Microsoft.Storage" in resource_type:
        return "Storage"
    elif "Microsoft.KeyVault" in resource_type:
        return "Security"
    elif "Microsoft.Insights" in resource_type or "OperationalInsights" in resource_type:
        return "Monitoring"
    elif "Microsoft.ServiceBus" in resource_type:
        return "Messaging"
    elif "Microsoft.Portal" in resource_type:
        return "Governance/UX"
    elif "Microsoft.RecoveryServices" in resource_type:
        return "Backup & Recovery"
    else:
        return "Other"

def get_dependencies(resource_type):
    deps = []
    if resource_type == "Microsoft.Web/sites":
        deps = ["App Service Plan", "Database"]
    elif resource_type == "Microsoft.Web/serverFarms":
        deps = ["VNet (if ASE)"]
    elif resource_type == "Microsoft.Sql/servers/databases":
        deps = ["SQL Server", "VNet (Private Endpoint)"]
    elif resource_type == "Microsoft.Sql/servers":
        deps = ["VNet (Private Endpoint)"]
    elif resource_type == "Microsoft.Compute/virtualMachines":
        deps = ["VNet", "NIC", "NSG", "Disk"]
    elif resource_type == "Microsoft.Network/privateEndpoints":
        deps = ["VNet", "Subnet"]
    elif resource_type == "Microsoft.Network/networkInterfaces":
        deps = ["VNet", "Subnet"]
    elif resource_type == "Microsoft.Network/networkSecurityGroups":
        deps = ["Subnet/NIC"]
    elif resource_type == "Microsoft.Storage/storageAccounts":
        deps = ["VNet (Private Endpoint)"]
    elif resource_type == "Microsoft.KeyVault/vaults":
        deps = ["VNet (Private Endpoint)"]
    elif resource_type == "Microsoft.ServiceBus/namespaces":
        deps = ["VNet (Private Endpoint if enabled)"]
    else:
        deps = ["None/Minimal"]
    return "; ".join(deps)

def get_migration_readiness(resource_type):
    if resource_type.startswith("Microsoft.Web/") or \
       resource_type.startswith("Microsoft.Sql/") or \
       resource_type.startswith("Microsoft.Storage/") or \
       resource_type.startswith("Microsoft.Compute/") or \
       resource_type.startswith("Microsoft.KeyVault/") or \
       resource_type.startswith("Microsoft.Network/"):
        return "Redeploy"
    elif resource_type.startswith("Microsoft.Portal/") or \
         resource_type.startswith("Microsoft.Insights/") or \
         resource_type.startswith("Microsoft.RecoveryServices/"):
        return "Rebuild"
    else:
        return "Redeploy"

# Parse each resource
for r in resources:
    name = r.get('name', '')
    rtype = r.get('type', '')
    rg = r.get('resourceGroup', '')
    location = r.get('location', '')
    sku = r.get('sku', {}).get('name') or r.get('properties', {}).get('sku', {}).get('name', 'N/A')
    category = get_category(rtype)
    deps = get_dependencies(rtype)
    readiness = get_migration_readiness(rtype)

    data.append({
        "ResourceName": name,
        "ResourceType": rtype,
        "ResourceGroup": rg,
        "Location": location,
        "SKU": sku,
        "Category": category,
        "DependsOn": deps,
        "MigrationReadiness": readiness
    })

# Create DataFrame
df = pd.DataFrame(data)

# Export to CSV
df.to_csv("azure-resource-dependency-matrix.csv", index=False)
print("✅ Dependency matrix exported as 'azure-resource-dependency-matrix.csv'")
