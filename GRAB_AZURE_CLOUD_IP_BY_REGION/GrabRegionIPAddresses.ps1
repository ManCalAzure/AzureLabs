### Needs Automation Account, [Needs modules Az.Profile, Az.Networking, Az.Resources], Runbook to execute this script
### Script can be more elaborate, but this is its simplest form.
### Populate script variables - Specify a region.
### Enter the region below. In this example, you will pull all Azure clould IPs for East US region
$azureRegion = 'eastus'

### Azure Region search 
$azureRegionSearch = '*' + $azureRegion + '*'
### Authenticate with Azure Automation account
$credential = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection"
    $servicePrincipalConnection = Get-AutomationConnection -Name $credential        

    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
}
catch {
 if (!$servicePrincipalConnection)
 {
 $ErrorMessage = "Connection $credential not found."
 throw $ErrorMessage
 } else{
 Write-Error -Message $_.Exception
 throw $_.Exception
 }
}
### Locations Array
[array]$locations = Get-AzLocation | Where-Object {$_.Location -like $azureRegionSearch}

### Create and populate the array with the IP ranges of each datacenter in the specified variable $azureRegionSearch
$IPRanges = @()
foreach($location in $locations){
 $IPRanges += Get-MicrosoftAzureDatacenterIPRange -AzureRegion $location.DisplayName
}
## Grab IPRanges, sort them, and give outpout
$IPRanges = $IPRanges | Sort-Object
Write-Output $IPRanges
