# Set output file name
$outputFile = "azure-resource-dependency-matrix.csv"

# Get all resources in the subscription
Write-Host "Fetching all resources in the current subscription..."
$resources = az resource list --query "[].{Name:name,Type:type,ResourceGroup:resourceGroup,Id:id}" --output json | ConvertFrom-Json

# Initialize result array
$dependencyList = @()

# Loop through each resource and check ARM dependencies
foreach ($res in $resources) {
    $resourceId = $res.Id
    $resourceName = $res.Name
    $resourceType = $res.Type
    $resourceGroup = $res.ResourceGroup

    # Fetch full resource details (including properties)
    $resourceDetails = az resource show --ids $resourceId --output json | ConvertFrom-Json

    # Check for dependsOn (exists in ARM templates, so we need to infer from relationships)
    $dependsOn = @()

    # Identify dependencies based on type and properties
    switch -Wildcard ($resourceType) {
        "Microsoft.Web/sites" {
            if ($resourceDetails.properties.serverFarmId) {
                $dependsOn += "App Service Plan"
            }
            if ($resourceDetails.properties.siteConfig?.vnetRouteAll) {
                $dependsOn += "Virtual Network"
            }
            if ($resourceDetails.properties.connectionStrings) {
                $dependsOn += "Database (SQL/Other)"
            }
        }
        "Microsoft.Web/serverFarms" {
            $dependsOn += "Virtual Network (ASE) if used"
        }
        "Microsoft.Sql/servers/databases" {
            $dependsOn += "SQL Server"
            if ($resourceDetails.properties.privateEndpointConnections.Count -gt 0) {
                $dependsOn += "Virtual Network (Private Endpoint)"
            }
        }
        "Microsoft.Sql/servers" {
            if ($resourceDetails.properties.privateEndpointConnections.Count -gt 0) {
                $dependsOn += "Virtual Network (Private Endpoint)"
            }
        }
        "Microsoft.Compute/virtualMachines" {
            $dependsOn += "Virtual Network, Network Interface, NSG"
            if ($resourceDetails.properties.storageProfile) {
                $dependsOn += "Storage Account or Managed Disks"
            }
        }
        "Microsoft.Network/privateEndpoints" {
            $dependsOn += "Virtual Network, Subnet"
        }
        "Microsoft.Network/networkInterfaces" {
            $dependsOn += "Virtual Network, Subnet"
        }
        "Microsoft.Network/networkSecurityGroups" {
            $dependsOn += "Subnets or Network Interfaces"
        }
        "Microsoft.Storage/storageAccounts" {
            if ($resourceDetails.properties.privateEndpointConnections.Count -gt 0) {
                $dependsOn += "Virtual Network (Private Endpoint)"
            }
        }
        "Microsoft.KeyVault/vaults" {
            if ($resourceDetails.properties.privateEndpointConnections.Count -gt 0) {
                $dependsOn += "Virtual Network (Private Endpoint)"
            }
        }
        default {
            # No specific dependency logic, leave blank
        }
    }

    # Add to dependency list
    $dependencyList += [PSCustomObject]@{
        ResourceName  = $resourceName
        ResourceType  = $resourceType
        ResourceGroup = $resourceGroup
        DependsOn     = if ($dependsOn.Count -gt 0) { ($dependsOn -join "; ") } else { "None/Minimal" }
    }
}

# Export to CSV
$dependencyList | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host "Dependency Matrix exported to $outputFile"
