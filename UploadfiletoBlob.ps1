# Input bindings are passed in via param block.
param($GtStgAcc)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# SPN login to upload file. This needs to be read from Env variables
$tenantId = [Environment]::GetEnvironmentVariable('UCAPI_TENANTID')
$thumb = [Environment]::GetEnvironmentVariable('ALPHA_SPN_THUMBID')
$appId = [Environment]::GetEnvironmentVariable('ALPHA_SPN_APPID')
$appName = [Environment]::GetEnvironmentVariable('ALPHA_SPN_APPNAME')

Write-Host "Connecting Azure through $appName SPN login to call UC API"

# Get all subscriptions
try {
    Connect-AzAccount -ServicePrincipal -Tenant $tenantId -CertificateThumbprint $thumb -ApplicationId $appId
    $subscriptions = Get-AzSubscription
} catch {
    Write-Warning "Failed to connect to Azure with SPN login. Skipping."
    return
}

# Define the tag key to filter by
$tagKey = "CyberDefence"

# Initialize an array to store the results
$strg = @()

foreach ($subscription in $subscriptions) {
    try {
        # Set the current subscription context
        Set-AzContext -SubscriptionId $subscription.Id
        # Get all storage accounts in the current subscription
        $storageAccounts = Get-AzStorageAccount | Where-Object { $_.Tags.ContainsKey($tagKey) }
    } catch {
        Write-Warning "Failed to set context for subscription: $($subscription.Name). Skipping."
        continue
    }
    foreach ($storageAccount in $storageAccounts) {
        # Get the metrics for the storage account
        $resourceId = "/subscriptions/$($subscription.Id)/resourceGroups/$($storageAccount.ResourceGroupName)/providers/Microsoft.Storage/storageAccounts/$($storageAccount.StorageAccountName)"
        $uri = "https://management.azure.com/$($resourceId)/providers/Microsoft.Insights/metrics?api-version=2023-10-01&metricnames=UsedCapacity&aggregation=Average"

        try {
            $response = Invoke-AzRestMethod -Method Get -Uri $uri
            $metrics = $response.Content | ConvertFrom-Json
            $usedCapacityMetric = $metrics.value | Where-Object { $_.name.value -eq "UsedCapacity" }

            if ($usedCapacityMetric) {
                $averageCapacity = $usedCapacityMetric.timeseries.data.average | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            } else {
                $averageCapacity = 0
            }
        } catch {
            Write-Warning "Failed to retrieve metrics for storage account: $($storageAccount.StorageAccountName). Skipping."
            continue
        }

        try {
            $ctx = $storageAccount.Context
            $containers = Get-AzStorageContainer -Context $ctx | Where-Object { $_.Name -eq "landing" }
            $objresults =@()
            foreach ($container in $containers) {
                $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx | Where-Object { $_.Name -like "internal/*" }
                # Extract unique directories within the "internal" directory
                $directories = $blobs | ForEach-Object {
                    $parts = $_.Name.Split('/')
                    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
                        $parts[0..$i] -join '/'
                    }
                } | Sort-Object -Unique
                $objresults += [PSCustomObject]@{
                    SubscriptionName   = $subscription.Name
                    ResourceGroup    = $storageAccount.ResourceGroupName
                    StorageAccount    = $storageAccount.StorageAccountName
                    ContainerName    = $container.Name
                    UsedCapacityInBytes = $averageCapacity
                    TagName       = $tagKey
                    TagValue       = $storageAccount.Tags[$tagKey]
                    Directories     = $directories -join ", "
                }
         
                $strg += $objresults 
            }
            Write-Host "Completed fetching storage account details"
        }
        catch {
            $_.ErrorDetails.Message
            $_
            Write-Host "Ignoring exception...."
        }
    }
}
    #$results | Format-Table -AutoSize
    #Write-Host "Completed fetching storage account details"
    # Create folder to store source path
$localPath = "$(Get-Location)\strgacctmp"
If (Get-ChildItem -Path $localPath -Force -ErrorAction SilentlyContinue) {
  Write-Host "Folder already Exists!"
}
else {
  New-Item -Path "$localPath" -ItemType 'Directory' -Name strgacctmp -Force -ErrorAction Stop
  Write-Host "New Folder unitycatalogtemp Created!"
}
function uploadFileToBlob {
      Param(
        [String] $LocalFilePath,
        [String] $TargetFileName
      )
      $tenantId = [Environment]::GetEnvironmentVariable('UCAPI_TENANTID')
      $storage_account = [Environment]::GetEnvironmentVariable('ADLS_STORAGE_ACCOUNT')
      $subscription = [Environment]::GetEnvironmentVariable('ADLS_SUBSCRIPTION_NAME')
      $filesystemName = [Environment]::GetEnvironmentVariable('ADLS_CONTAINER_NAME')
      $destPath = [Environment]::GetEnvironmentVariable('ADLS_FOLDER_PATH_UC_DASHBOARD')
      Write-Host " ----Retrieved App Settings from Function App--- "
      Write-Host "ADLS_STORAGE_ACCOUNT - $storage_account"
      Write-Host "ADLS_SUBSCRIPTION_NAME - $subscription"
      Write-Host "ADLS_CONTAINER_NAME - $filesystemName"
      Write-Host "Source -$LocalFilePath"
      Write-Host "destination Path -$destPath"
      Write-Host "Path from where files will be uploaded :$LocalFilePath"
      Write-Host "-------------------------"
      Write-Host "selecting subscription: $subscription"
    #SPN login to upload file. This need to read from Env variable
      $thumb = [Environment]::GetEnvironmentVariable('ALPHA_SPN_THUMBID')
      $appId = [Environment]::GetEnvironmentVariable('ALPHA_SPN_APPID')
      $appName = [Environment]::GetEnvironmentVariable('ALPHA_SPN_APPNAME')
      Write-Host "Connecting Azure through $appName SPN login to call UC API"
      Connect-AzAccount -ServicePrincipal -Tenant $tenantId -CertificateThumbprint $thumb -ApplicationId $appId
      Update-AzConfig -DefaultSubscriptionForLogin $subscription
      Write-Host "Update-AzConfig Successful for Subscription - $subscription"
      $ctx = New-AzStorageContext -StorageAccountName $storage_account -UseConnectedAccount -ErrorAction Stop
    try {
        $destPath += "/" + $TargetFileName
        New-AzDataLakeGen2Item -Context $ctx -FileSystem $filesystemName -Path $destPath -Source $LocalFilePath -ErrorAction Stop -Force
        Start-Sleep -seconds 2
        # Will execute on successful completion of folder upload
        Write-Host "File uploaded successfully!"
      }
      catch {
        Write-Output " Error occured as below"
        $_
        exit
      }
    }
    $current_date = Get-Date -Format FileDate
Write-Host "Storage account details-"
# Export to CSV    
$CsvPath = $localPath + "\strgaccsize$current_date.csv"
$strg | Export-Csv -Path $CsvPath -NoTypeInformation
#Upload to blob
$targetFileName = "strgaccsize$($current_date).csv"
uploadFileToBlob -LocalFilePath $CsvPath -TargetFileName $targetFileName
#Need to delete locally stored files in folder unitycatalogtmp
Get-ChildItem -Path $localPath -Filter *.csv | Remove-Item -Recurse
