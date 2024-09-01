using namespace System.Net
param($Request, $TriggerMetadata)
$ErrorActionPreference = "STOP"
$AppId = $env:AccountAdminSPN_AppId
$Thumb = $env:AccountAdminSPN_Thumbprint
$TenantId = $env:TenantId
               
$Output = New-Object -TypeName hashtable
#Map the workspace and update the workspace in the Output
MapToWorkspace -MetastoreRegion $Request.Body.MetastoreRegion -Output $Output
$Workspace = $Output.Workspace
$apiEndpoint = "https://$($Request.Body.WorkspaceName)/api/2.1/unity-catalog/external-locations/$($Request.Body.OldExternalLocationName)"
Write-Host "API Endpoint: $apiEndpoint"
try {
      # Connect to Azure using the service principal
      Connect-AzAccount `
        -CertificateThumbprint $Thumb `
        -ApplicationId $AppId `
        -Tenant $TenantId `
        -ServicePrincipal
      $Response = New-Object -TypeName hashtable
      # Define the update endpoint and request body
        $UpdateCatalogReqBody = @{
        new_name = $Request.Body.NewExternalLocationName
        credential_name = $Request.Body.credentialname
      } | ConvertTo-Json -Depth 15
     
      Write-Host "Update Request Body: $($UpdateCatalogReqBody)"
    # Invoke the API to update the catalog
     
      Invoke-Api -ApiEndpoint $apiEndpoint -Response $Response -Body $UpdateCatalogReqBody -Operation "PATCH" -Force $true
      Write-Host "Catalog updated successfully: $($Request.Body.OldExternalLocationName) to $($Request.Body.NewExternalLocationName)"
     
      # Send a success response
      Send-Response -Status $Response.StatusCode -Body @{
        status   = "success"
        apiEndpoint = $apiEndpoint
        output   = $Output
      }
    }
    catch {
      # Handle any errors
      $errorMessage = $_.Exception.Message
      Send-Response -Status $Response.StatusCode -Body @{
        status = "error"
        message = "An error occurred: $errorMessage"
      }
      Write-Host $apiEndpoint
    }