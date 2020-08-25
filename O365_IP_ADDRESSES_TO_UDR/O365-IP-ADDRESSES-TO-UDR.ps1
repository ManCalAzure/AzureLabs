## Auth using the desired Azure Automation account
## First create an automation account (Run As Account), import Modules Az.Accounts, Az.Compute, Az.Network, Az.Profile, Az.Resources, run this
##script as a powershell runbook.
$cred = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection"
    $servicePrincipalConnection = Get-AutomationConnection -Name $cred        

    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
}
catch {
 if (!$servicePrincipalConnection)
 {
 $ErrorMessage = "Connection $cred not found."
 throw $ErrorMessage
 } else{
 Write-Error -Message $_.Exception
 throw $_.Exception
 }
}
### Script to grab the Office 365 IP addresses, both IPv4 and IPv6. However, we are only intersted in IPv4 for now.
# web service root URL
$ws = "https://endpoints.office.com"
# path where output files will be stored
$versionpath = $Env:TEMP + "\O365_endpoints_latestversion.txt"
$datapath = $Env:TEMP + "\O365_endpoints_data.txt"

# fetch client ID and version if version file exists; otherwise create new file and client ID
if (Test-Path $versionpath) {
    $content = Get-Content $versionpath
    $clientRequestId = $content[0]
    $lastVersion = $content[1]
    Write-Output ("Version file exists! Current version: " + $lastVersion)
}
else {
    $clientRequestId = [GUID]::NewGuid().Guid
    $lastVersion = "0000000000"
    @($clientRequestId, $lastVersion) | Out-File $versionpath
}

# call version method to check the latest version, and pull new data if version number is different
$version = Invoke-RestMethod -Uri ($ws + "/version/Worldwide?clientRequestId=" + $clientRequestId)
if ($version.latest -gt $lastVersion) {
    # write the new version number to the version file
    @($clientRequestId, $version.latest) | Out-File $versionpath
    # invoke endpoints method to get the new data
    $endpointSets = Invoke-RestMethod -Uri ($ws + "/endpoints/Worldwide?clientRequestId=" + $clientRequestId)
    # filter results for Allow and Optimize endpoints, and transform these into custom objects with port and category
    # URL results
    $flatUrls = $endpointSets | ForEach-Object {
        $endpointSet = $_
        $urls = $(if ($endpointSet.urls.Count -gt 0) { $endpointSet.urls } else { @() })
        $urlCustomObjects = @()
        if ($endpointSet.category -in ("Allow", "Optimize")) {
            $urlCustomObjects = $urls | ForEach-Object {
                [PSCustomObject]@{
                    category = $endpointSet.category;
                    url      = $_;
                    tcpPorts = $endpointSet.tcpPorts;
                    udpPorts = $endpointSet.udpPorts;
                }
            }
        }
        $urlCustomObjects
    }
    # IPv4 results
    $flatIp4s = $endpointSets | ForEach-Object {
        $endpointSet = $_
        $ips = $(if ($endpointSet.ips.Count -gt 0) { $endpointSet.ips } else { @() })
        # IPv4 strings contain dots
        $ip4s = $ips | Where-Object { $_ -like '*.*' }
        $ip4CustomObjects = @()
        if ($endpointSet.category -in ("Allow", "Optimize")) {
            $ip4CustomObjects = $ip4s | ForEach-Object {
                [PSCustomObject]@{
                    category = $endpointSet.category;
                    ip = $_;
                    tcpPorts = $endpointSet.tcpPorts;
                    udpPorts = $endpointSet.udpPorts;
                }
            }
        }
        $ip4CustomObjects
    }
    # IPv6 results
    $flatIp6s = $endpointSets | ForEach-Object {
        $endpointSet = $_
        $ips = $(if ($endpointSet.ips.Count -gt 0) { $endpointSet.ips } else { @() })
        # IPv6 strings contain colons
        $ip6s = $ips | Where-Object { $_ -like '*:*' }
        $ip6CustomObjects = @()
        if ($endpointSet.category -in ("Optimize")) {
            $ip6CustomObjects = $ip6s | ForEach-Object {
                [PSCustomObject]@{
                    category = $endpointSet.category;
                    ip = $_;
                    tcpPorts = $endpointSet.tcpPorts;
                    udpPorts = $endpointSet.udpPorts;
                }
            }
        }
        $ip6CustomObjects
    }
    ##This next like is just to see the results of the above script
    ($flatIp4s.ip | Sort-Object -Unique) | Out-String
    ###This next like I commented out since we dont need it here for our purposes
    #($flatIp4s.ip | Sort-Object -Unique) | Out-File $datapath -Append
}
else {
    #Write-Host "Office 365 worldwide commercial service instance endpoints are up-to-date."
}

##Script variables (These can be Variables in automation account).
$resourceGroupName = 'RG-MANNY-INFRA'
$resourceLocation = 'centralus'
$vNetName = 'VNET1'

##Select the virtual network and grab all subnets, except 'GatewaySubnet' & 'AzureBastionSubnet' if they exist. 
$vNet = Get-AzVirtualNetwork `
 -ResourceGroupName $resourceGroupName `
 -Name $vNetName
[array]$subnets = $vnet.Subnets | Where-Object {$_.Name -ne 'GatewaySubnet'} | Where-Object {$_.Name -ne 'AzureBastionSubnet'} | Select-Object Name

## Take each subnet in the VNET and create a route table with the subnet name and add -RT
foreach($subnet in $subnets){
$RouteTableName = $subnet.Name + '-RT'
$vNet = Get-AzVirtualNetwork `
 -ResourceGroupName $resourceGroupName `
 -Name $vNetName

## Create a new route table if one does not already exist
 if ((Get-AzRouteTable -Name $RouteTableName -ResourceGroupName $resourceGroupName) -eq $null){
 $RouteTable = New-AzRouteTable `
 -Name $RouteTableName `
 -ResourceGroupName $resourceGroupName `
 -Location $resourceLocation
 }

 ### If the route table exists, remove it. 
 else {
 $RouteTable = Get-AzRouteTable `
 -Name $RouteTableName `
 -ResourceGroupName $resourceGroupName
 $routeConfigs = Get-AzRouteConfig -RouteTable $RouteTable
 foreach($config in $routeConfigs){
 Remove-AzRouteConfig -RouteTable $RouteTable -Name $config.Name | Out-Null
 }
 }

## Create a routing configuration for each IP range and give each a descriptive name
 foreach($ip in $flatIp4s.ip){
 $routeName = 'o365-' + $ip.Replace('/','-') 
 Add-AzRouteConfig `
 -Name $routeName `
 -AddressPrefix $ip `
 -NextHopType Internet `
 -RouteTable $RouteTable | Out-Null
 }

 ## This route is also needed for Microsoft's KMS servers for Windows activation
 Add-AzRouteConfig `
 -Name 'AzureKMS' `
 -AddressPrefix 23.102.135.246/32 `
 -NextHopType Internet `
 -RouteTable $RouteTable

## Apply the route table to the subnet
Set-AzRouteTable -RouteTable $RouteTable
$o365routes = $vNet.Subnets | Where-Object Name -eq $subnet.Name
$o365routes.RouteTable = $RouteTable

## Update the virtual network with the new subnet configuration
Set-AzVirtualNetwork -VirtualNetwork $vNet -Verbose
}