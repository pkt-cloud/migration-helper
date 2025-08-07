# Step 1: Set output file name
$outputFile = "azure-resource-detailed-dependency-matrix.csv"

# Step 2: Let the user choose a subscription
Write-Host ""
Write-Host "Available Azure Subscriptions:"
Write-Host ""

# Get the list of subscriptions
$subscriptions = az account list --query "[].{Name:name, Id:id}" --output json | ConvertFrom-Json

# Display subscriptions with numbers
for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $number = $i + 1
    $sub = $subscriptions[$i]
    Write-Host "$number. $($sub.Name) ($($sub.Id))"
}

# Ask user to pick a subscription
do {
    $selection = Read-Host "Enter the number of the subscription you want to use"
} while (-not ($selection -as [int]) -or $selection -lt 1 -or $selection -gt $subscriptions.Count)

# Set the selected subscription
$selectedSub = $subscriptions[$selection - 1]
az account set --subscription $selectedSub.Id
Write-Host ""
Write-Host "Subscription set to: $($selectedSub.Name)"
Write-Host ""

# Step 3: Get all resources from the subscription
Write-Host "Fetching all Azure resources..."
$resources = az resource list --output json | ConvertFrom-Json
$results = @()

# Function to classify resources
function Get-Category($type) {
    switch -Wildcard ($type) {
        "*Microsoft.Compute/*" { return "Compute" }
        "*Microsoft.Web/*" { return "App Services" }
        "*Microsoft.Sql/*" { return "Database" }
        "*Microsoft.Network/*" { return "Networking" }
        "*Microsoft.Storage/*" { return "Storage" }
        "*Microsoft.KeyVault/*" { return "Security" }
        "*Microsoft.RecoveryServices/*" { return "Backup & Recovery" }
        "*Microsoft.OperationalInsights/*" { return "Monitoring" }
        "*Microsoft.Insights/*" { return "Monitoring" }
        "*microsoft.insights/*" { return "Monitoring" }
        "*Microsoft.ServiceBus/*" { return "Messaging" }
        "*Microsoft.Portal/*" { return "Governance/UX" }
        "*Microsoft.Security/*" { return "Security" }
        "*Microsoft.OperationsManagement/*" { return "Monitoring" }
        default { return "Other" }
    }
}

# Function to detect dependencies
function Get-Dependencies($type, $details) {
    $deps = @()

    if ($type -like "Microsoft.Web/sites") {
        if ($details.properties.serverFarmId) { $deps += "App Service Plan" }
        if ($details.properties.connectionStrings) { $deps += "Database (SQL/Other)" }
    }
    elseif ($type -like "Microsoft.Web/serverFarms") {
        $deps += "VNet (if using ASE)"
    }
    elseif ($type -like "Microsoft.Sql/servers/databases") {
        $deps += "SQL Server"
        if ($details.properties.privateEndpointConnections.Count -gt 0) { $deps += "VNet (Private Endpoint)" }
    }
    elseif ($type -like "Microsoft.Sql/servers") {
        if ($details.properties.privateEndpointConnections.Count -gt 0) { $deps += "VNet (Private Endpoint)" }
    }
    elseif ($type -like "Microsoft.Compute/virtualMachines") {
        $deps += "VNet, NIC, NSG, Disk"
    }
    elseif ($type -like "Microsoft.Network/privateEndpoints") {
        $deps += "VNet, Subnet"
    }
    elseif ($type -like "Microsoft.Network/networkInterfaces") {
        $deps += "VNet, Subnet"
    }
    elseif ($type -like "Microsoft.Network/networkSecurityGroups") {
        $deps += "Subnet/NIC"
    }
    elseif ($type -like "Microsoft.Storage/storageAccounts") {
        if ($details.properties.privateEndpointConnections.Count -gt 0) { $deps += "VNet (Private Endpoint)" }
    }
    elseif ($type -like "Microsoft.KeyVault/vaults") {
        if ($details.properties.privateEndpointConnections.Count -gt 0) { $deps += "VNet (Private Endpoint)" }
    }
    elseif ($type -like "Microsoft.ServiceBus/namespaces") {
        $deps += "VNet (Private Endpoint if enabled)"
    }
    else {
        $deps += "None/Minimal"
    }

    return ($deps -join "; ")
}

# Function to determine migration method
function Get-MigrationReadiness($type) {
    if ($type -like "Microsoft.Web/sites") { return "Redeploy" }
    elseif ($type -like "Microsoft.Web/serverFarms") { return "Redeploy" }
    elseif ($type -like "Microsoft.Sql/servers*") { return "Redeploy" }
    elseif ($type -like "Microsoft.Storage/storageAccounts") { return "Redeploy" }
    elseif ($type -like "Microsoft.Compute/virtualMachines") { return "Redeploy" }
    elseif ($type -like "Microsoft.KeyVault/vaults") { return "Redeploy" }
    elseif ($type -like "Microsoft.Network/*") { return "Redeploy" }
    elseif ($type -like "Microsoft.Portal/dashboards") { return "Rebuild" }
    elseif ($type -like "Microsoft.Insights/*") { return "Rebuild" }
    elseif ($type -like "Microsoft.RecoveryServices/*") { return "Rebuild" }
    else { return "Redeploy" }
}

# Step 4: Loop through resources and gather information
Write-Host "Analyzing resources..."

foreach ($res in $resources) {
    $resName = $res.name
    $resType = $res.type
    $resGroup = $res.resourceGroup
    $resId = $res.id
    $resLocation = $res.location
    $resSku = "N/A"
    $lastModified = "Unknown"

    # Get detailed resource info
    $details = az resource show --ids $resId --output json | ConvertFrom-Json

    # Try to get SKU
    if ($details.sku -and $details.sku.name) {
        $resSku = $details.sku.name
    }
    elseif ($details.properties -and $details.properties.sku -and $details.properties.sku.name) {
        $resSku = $details.properties.sku.name
    }

    # Try to get last modified date
    if ($details.properties -and $details.properties.lastModifiedTime) {
        $lastModified = $details.properties.lastModifiedTime
    }
    elseif ($details.tags -and $details.tags.LastModified) {
        $lastModified = $details.tags.LastModified
    }

    # Categorize, detect dependencies and readiness
    $category = Get-Category $resType
    $dependencies = Get-Dependencies $resType $details
    $migrationPlan = Get-MigrationReadiness $resType

    # Add record
    $results += [PSCustomObject]@{
        ResourceName       = $resName
        ResourceType       = $resType
        ResourceGroup      = $resGroup
        Location           = $resLocation
        SKU                = $resSku
        LastModifiedDate   = $lastModified
        Category           = $category
        DependsOn          = $dependencies
        MigrationReadiness = $migrationPlan
    }
}

# Step 5: Export results to CSV
Write-Host "Exporting results..."
$results | Export-Csv -Path $outputFile -NoTypeInformation
Write-Host ""
Write-Host "Export complete! File saved as $outputFile"
