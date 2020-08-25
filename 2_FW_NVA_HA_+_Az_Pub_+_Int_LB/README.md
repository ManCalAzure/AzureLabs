#### Azure Network Security Lab - In this lab, we will deploy 2 firewalls (Juniper vSRX NVAs) between both a Public and Internal load balancer. This design provides Active/Active high availability (HA) for both outbound and inbound connections. 

#### Topology
<table><tr><td>
    <img src="https://github.com/ManCalAzure/AzureLabs/blob/master/2_FW_NVA_HA_%2B_Az_Pub_%2B_Int_LB/topo-diagram.png" lt="" title="Lab Topology" width="400" height="600"  />
</td></tr></table>

### Lab Configuration Elements
<pre lang= >
<b>1-</b> Create a resource group
<b>2-</b> Create a storage account (bootdiags)
<b>3-</b> Create VNETS (hub and spokes)
<b>4-</b> Create Subnets
<b>5-</b> Create the VNET peerings between the hub and spokes
<b>6-</b> Create public IPs for the firewalls
<b>7-</b> Create vNICs (For firewalls & VMs)
<b>8-</b> Create control plane (management) and data plane Network Security Groups (UNTRUST & TRUST) (NSGs)
<b>9-</b> Associate the vNICs with their correponding NSGs
<b>10-</b> Create the firewall and Test web server
<b>11-</b> Create the Azure <b>Internal</b> load balancer
  - Backend pool
  - Probe
  - LB rule - with <b>HA ports</b>
  - Associate the firewall TRUST vNICs with the internal LB backendpool
<b>12-</b> Create the Azure <b>Public</b> load balancer
  - Backend poool
  - Probe
  - LB rule - with <b>floating IP</b>
  - Associate the firewall UNTRUST vNICs with the LB backendpool

<b>13-</b> Create the spoke UDR + Route which will route traffic to the internal LB VIP
<b>14-</b> Associate the UDR with the spoke subnet
<b>15-</b> Configure the firewalls and test web servers
</pre>

### Create a resource group
<pre lang= >
az group create --name RG-LB-TEST --location eastus --output table
</pre>

### Create a storage account for bootdiags
<pre lang= >
az storage account create -n mcbootdiag -g RG-LB-TEST -l eastus --sku Standard_LRS
</pre>

### Create the HUB and a SPOKE VNET
<pre lang= >
az network vnet create --name HUB-VNET --resource-group RG-LB-TEST --location eastus --address-prefix 10.0.0.0/16
az network vnet create --name SPOKE-VNET --resource-group RG-LB-TEST --location eastus --address-prefix 10.80.0.0/16
</pre>

### Create the Subnets in HUB and SPOKE VNETs
<pre lang= >
az network vnet subnet create --vnet-name HUB-VNET --name MGMT --resource-group RG-LB-TEST --address-prefixes 10.0.254.0/24 --output table
az network vnet subnet create --vnet-name HUB-VNET --name UNTRUST --resource-group RG-LB-TEST --address-prefixes 10.0.0.0/24 --output table
az network vnet subnet create --vnet-name HUB-VNET --name TRUST --resource-group RG-LB-TEST --address-prefixes 10.0.1.0/24 --output table
az network vnet subnet create --vnet-name SPOKE-VNET --name VMWORKLOADS --resource-group RG-LB-TEST --address-prefixes 10.80.99.0/24 --output table
</pre>

### VNET Peer HUB and SPOKE VNETs
<pre lang= >
az network vnet peering create -g RG-LB-TEST --name HUB-TO-SPOKE --vnet-name HUB-VNET --remote-vnet SPOKE-VNET --allow-forwarded-traffic --allow-vnet-access --output table
az network vnet peering create -g RG-LB-TEST --name SPOKE-TO-HUB --vnet-name SPOKE-VNET --remote-vnet HUB-VNET --allow-forwarded-traffic --allow-vnet-access --output table
</pre>

### Create the Public IPs - When utilizing Public IPs with Standard SKU, an NSG is required on the Subnet/vNIC. Two public IPs will be created per Firewall NVA, and 1 for the Public LB. 1) fxp0 - management interface 2) ge0 - UNTRUST/Interface facing interface
<pre lang= >
vSRX1
az network public-ip create --name VSRX1-PIP-1 --allocation-method Static --resource-group RG-LB-TEST --location eastus --sku Standard
az network public-ip create --name VSRX1-PIP-2 --allocation-method Static --resource-group RG-LB-TEST --location eastus --sku Standard
vSRX2
az network public-ip create --name VSRX2-PIP-1 --allocation-method Static --resource-group RG-LB-TEST --location eastus --sku Standard
az network public-ip create --name VSRX2-PIP-2 --allocation-method Static --resource-group RG-LB-TEST --location eastus --sku Standard
Az Load Balancer Public IP
az network public-ip create --name AZ-PUB-LB-PIP --allocation-method Static --resource-group RG-LB-TEST --location eastus --sku Standard
</pre>

### Create the vNICs
fxp0 = Out of band management interface on vSRXs
<pre lang= >
VSRX1
az network nic create --resource-group RG-LB-TEST --location eastus --name VSRX1-fxp0 --vnet-name HUB-VNET --subnet MGMT --public-ip-address  VSRX1-PIP-1 --private-ip-address 10.0.254.4 
az network nic create --resource-group RG-LB-TEST --location eastus --name VSRX1-ge0 --vnet-name HUB-VNET --subnet UNTRUST --public-ip-address  VSRX1-PIP-2 --private-ip-address 10.0.0.4 --ip-forwarding
az network nic create --resource-group RG-LB-TEST --location eastus --name VSRX1-ge1 --vnet-name HUB-VNET --subnet TRUST --private-ip-address 10.0.1.4 --ip-forwarding
VSRX2
az network nic create --resource-group RG-LB-TEST --location eastus --name VSRX2-fxp0 --vnet-name HUB-VNET --subnet MGMT --public-ip-address  VSRX2-PIP-1 --private-ip-address 10.0.254.5
az network nic create --resource-group RG-LB-TEST --location eastus --name VSRX2-ge0 --vnet-name HUB-VNET --subnet UNTRUST --public-ip-address  VSRX2-PIP-2 --private-ip-address 10.0.0.5
az network nic create --resource-group RG-LB-TEST --location eastus --name VSRX2-ge1 --vnet-name HUB-VNET --subnet TRUST --private-ip-address 10.0.1.5
Web Server VM
az network nic create --resource-group RG-LB-TEST --location eastus --name WEB-eth0 --vnet-name SPOKE-VNET --subnet VMWORKLOADS --private-ip-address 10.80.99.10
</pre>

### Create NSGs - Since I selected to use 'Standard' SKU public IP addresses explicitly defined NSG is required. It is also a good idea to plan subnet security and apply NSGs as a general best practice for security.
<pre lang= >
Contral Plane NSG (This NSG is assigned to the vSRX out-of-band management interrace (fxp0)
az network nsg create --resource-group RG-LB-TEST --name CP-NSG --location eastus
az network nsg rule create -g RG-LB-TEST --nsg-name CP-NSG -n ALLOW-SSH --priority 300 --source-address-prefixes Internet --destination-address-prefixes 10.0.254.0/24 --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow SSH to Management Subnet"
az network nsg rule create -g RG-LB-TEST --nsg-name CP-NSG -n ALLOW-ICMP --priority 301 --source-address-prefixes Internet --destination-address-prefixes 10.0.54.0/24 --destination-port-ranges * --protocol Icmp --description "Allow ICMP to FW OOB interface"

Untrust Subnet NSG (NSG applied to the untrusted transit subnet)
az network nsg create --resource-group RG-LB-TEST --name UNTRUST-NSG --location eastus
az network nsg rule create -g RG-LB-TEST --nsg-name UNTRUST-NSG -n ALLOW-HTTP --priority 200 --source-address-prefixes * --source-port-ranges * --destination-address-prefixes * --destination-port-ranges 80 --access Allow --protocol Tcp --description "Allow HTTP to Untrust Subnet"

Trust Subnet NSG (NGS applied to the trusted transit subnet)
az network nsg create --resource-group RG-LB-TEST --name TRUST-NSG --location eastus
az network nsg rule create -g RG-LB-TEST --nsg-name TRUST-NSG -n ALLOW-ALL --priority 200 --source-address-prefixes * --source-port-ranges * --destination-address-prefixes * --destination-port-ranges * --access Allow --protocol * --description "Allow All to Trust Subnet"

ADD an allow all outbound on Trust side******************

NSG Rule check
az network nsg rule show --name ALLOW-ALL --nsg-name TRUST-NSG -g RG-LB-TEST --output table
az network nsg rule show --name ALLOW-HTTP --nsg-name UNTRUST-NSG -g RG-LB-TEST --output table
az network nsg rule show --name ALLOW-SSH --nsg-name CP-NSG -g RG-LB-TEST --output table
az network nsg rule show --name ALLOW-ICMP --nsg-name CP-NSG -g RG-LB-TEST --output table

Associate vNICs with corresponding NSGs
az network nic update --resource-group RG-LB-TEST --name VSRX1-fxp0 --network-security-group CP-NSG
az network nic update --resource-group RG-LB-TEST --name VSRX2-fxp0 --network-security-group CP-NSG
az network nic update --resource-group RG-LB-TEST --name VSRX1-ge0 --network-security-group UNTRUST-NSG
az network nic update --resource-group RG-LB-TEST --name VSRX2-ge0 --network-security-group UNTRUST-NSG
az network nic update --resource-group RG-LB-TEST --name VSRX1-ge1 --network-security-group UNTRUST-NSG
az network nic update --resource-group RG-LB-TEST --name VSRX2-ge1 --network-security-group UNTRUST-NSG
</pre>

### At this point, we have created the following:
* Created the resource group
* Created a storage account in case bootdiags require it
* Created HUB & SPOKE VNETs
* Created TRUST, UNTRUST, and MGMT (firewall maangement) subnets
* Created the VNET peering (Hub to Spoke)
* Created the Public IP addresses for the firewalls and the load balancer
* Created the vNICs for the firewalls, and the web server
* Created the NSGs for the management subnet (MGT) and UNTRUST subnet.

<p style="page-break-after: always;">&nbsp;</p>
--------------------------------------------------------------------------------------------------------------
<p style="page-break-before: always;">&nbsp;</p>

### Create the vSRX Firewalls, and the web server VMs
<pre lang= >
<b>First - Accept the Juniper Networks license agreement</b>
In PowerShell
Get-AzureRmMarketplaceTerms -Publisher juniper-networks -Product vsrx-next-generation-firewall -Name vsrx-byol-azure-image | Set-AzureRmMarketplaceTerms -Accept

VSRX1
az vm create --resource-group RG-LB-TEST --location eastus --name VSRX1 --size Standard_DS3_v2 --nics VSRX1-fxp0 VSRX1-ge0 VSRX1-ge1 --image juniper-networks:vsrx-next-generation-firewall:vsrx-byol-azure-image:19.2.1 --admin-username lab-user --admin-password AzLabPass1234 --boot-diagnostics-storage mcbootdiag --no-wait

VSRX2
az vm create --resource-group RG-LB-TEST --location eastus --name VSRX2 --size Standard_DS3_v2 --nics VSRX2-fxp0 VSRX2-ge0 VSRX2-ge1 --image juniper-networks:vsrx-next-generation-firewall:vsrx-byol-azure-image:19.2.1 --admin-username lab-user --admin-password AzLabPass1234 --boot-diagnostics-storage mcbootdiag --no-wait

Web Server
az vm create -n WEB-SERVER -g RG-LB-TEST --image UbuntuLTS --admin-username lab-user --admin-password AzLabPass1234 --nics WEB-eth0 --boot-diagnostics-storage mcbootdiag --no-wait

Once the VM is up and running, run the following to update and install apache2:
1- sudo apt update
2- sudo apt upgrade -y
3- sudo apt install apache2 -y
</pre>

### Create ILB with front end IP, and backend pool name
<pre lang= >
az network lb create --resource-group RG-LB-TEST --name ILB-1 --frontend-ip-name ILB-1-FE --private-ip-address 10.0.1.254 --backend-pool-name ILB-BEPOOL --vnet-name HUB-VNET --subnet TRUST --location eastus --sku Standard

Output after created:
az network lb list -g RG-LB-TEST --output table
Location    Name    ProvisioningState    ResourceGroup    ResourceGuid
----------  ------  -------------------  ---------------  ------------------------------------
eastus      ILB-1   Succeeded            RG-LB-TEST       5deeeeb5-bfa9-4540-ab44-e94b7506c60f
</pre>

### Create ILB the probe
<pre lang= >
az network LB probe create --resource-group RG-LB-TEST --name ILB-PROBE1 --protocol tcp --port 22 --interval 30 --threshold 2 --lb-name ILB-1

Show the probe after created:
az network lb probe list --resource-group RG-LB-TEST --lb-name ILB-1 --output table
IntervalInSeconds    Name       NumberOfProbes    Port    Protocol    ProvisioningState    ResourceGroup
-------------------  ---------  ----------------  ------  ----------  -------------------  ---------------
30                   BE-PROBE1  2                 22      Tcp         Succeeded            RG-LB-TEST
</pre>

### Create the ILB LB rule with 'HA Ports'
<pre lang= >
az network lb rule create --resource-group RG-LB-TEST --name ILB-R1-HAPORTS --backend-pool-name ILB-BEPOOL --probe-name ILB-PROBE1 --protocol all --frontend-port 0 --backend-port 0 --lb-name ILB-1

Show the rule created:
az network lb rule list --lb-name ILB-1 -g RG-LB-TEST --output table

BackendPort    DisableOutboundSnat    EnableFloatingIp    EnableTcpReset    FrontendPort    IdleTimeoutInMinutes    LoadDistribution    Name            Protocol    ProvisioningState    ResourceGroup
-------------  ---------------------  ------------------  ----------------  --------------  ----------------------  ------------------  --------------  ----------  -------------------  ---------------
0              False                  False               False             0               4                       Default             ILB-R1-HAPORTS  All         Succeeded            RG-LB-TEST

</pre>

### Add trust side vNICs to backend pool utilized by the ILB
<pre lang= >
az network nic ip-config update --resource-group RG-LB-TEST --nic-name VSRX1-ge1 --name ipconfig1 --lb-address-pool ILB-BEPOOL --vnet-name HUB-VNET --subnet TRUST --lb-name ILB-1
az network nic ip-config update --resource-group RG-LB-TEST --nic-name VSRX2-ge1 --name ipconfig1 --lb-address-pool ILB-BEPOOL --vnet-name HUB-VNET --subnet TRUST --lb-name ILB-1
</pre>

### Creating the Azure public load balancer (PLB)
<pre lang= >
az network lb create --resource-group RG-LB-TEST --name AZ-PUB-LB --sku Standard --public-ip-address AZ-PUB-LB-PIP --no-wait
</pre>

### Create PLB the backend pool
<pre lang= >
az network LB address-pool create --lb-name AZ-PUB-LB --name PLB-BEPOOL --resource-group RG-LB-TEST
</pre>

### Create PLB the probe
<pre lang= >
az network LB probe create --resource-group RG-LB-TEST --name BE-PROBE1 --protocol tcp --port 22 --interval 30 --threshold 2 --lb-name AZ-PUB-LB
</pre>

### Create a PLB LB rule (Floating IP)
<pre lang= >
az network lb rule create --resource-group RG-LB-TEST --name LB-RULE-1 --backend-pool-name PLB-BEPOOL --probe-name BE-PROBE1 --protocol Tcp --frontend-port 80 --backend-port 80 --lb-name AZ-PUB-LB --floating-ip true --output table
</pre>

### Add the VSRX1-ge0 & VSRX2-ge0 vNICs to the PLB LB backend pool
<pre lang= >
az network nic ip-config update -g RG-LB-TEST --nic-name VSRX1-ge0 -n ipconfig1 --lb-address-pool PLB-BEPOOL --vnet-name hub-vnet --subnet UNTRUST --lb-name AZ-PUB-LB
az network nic ip-config update -g RG-LB-TEST --nic-name VSRX2-ge0 -n ipconfig1 --lb-address-pool PLB-BEPOOL --vnet-name hub-vnet --subnet UNTRUST --lb-name AZ-PUB-LB
</pre>

### Get a list of the public IPs, or specific instances public IPs
<pre lang= >
az network public-ip list --output table

Ror specific instance
az network public-ip show -g RG-LB-TEST --name VSRX1-PIP-1 --output table
</pre>

## At this point, all Azure elements have been deployed and configured.

### Since we are utilizing both a public and internal load balancer, you have to be mindful of flow symmetry/affinity. In order to preserve flow symmetry, you have to configure source NAT (SNAT) for egress flows. This ensures that traffic which egress a specific firewall VM, returns to that same firewall. 

### Need to create UDR to apply to the VMWORKLOADS subnet - UDR will route 0/0 to the internal LB VIP
<pre lang= >
Create the UDR
az network route-table create  --name UDR-TO-ILB --resource-group RG-LB-TEST -l eastus

Create the route
az network route-table route create --name DEF-TO-ILB -g RG-LB-TEST --route-table-name UDR-TO-ILB --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address 10.0.1.254

Route creation check
az network route-table route show -g RG-LB-TEST --name DEF-TO-ILB --route-table-name UDR-TO-ILB --output table

AddressPrefix    Name        NextHopIpAddress    NextHopType       ProvisioningState    ResourceGroup
---------------  ----------  ------------------  ----------------  -------------------  ---------------
0.0.0.0/0        DEF-TO-ILB  10.0.1.254          VirtualAppliance  Succeeded            RG-LB-TEST

</pre>

### Once the UDR is created, associate it or apply it to the VMWORKLOADS subnet.
<pre lang= >
az network vnet subnet update --vnet-name SPOKE-VNET --name VMWORKLOADS --resource-group RG-LB-TEST --route-table UDR-TO-ILB
</pre>

### Check web server effective route table to ensure UDR is applied
<pre lang= >
az network nic show-effective-route-table --name WEB-eth0 --resource-group RG-LB-TEST --output table

Source    State    Address Prefix    Next Hop Type    Next Hop IP
--------  -------  ----------------  ---------------  -------------
Default   Active   10.80.0.0/16      VnetLocal
Default   Active   10.0.0.0/16       VNetPeering
Default   Active   0.0.0.0/0         Internet
Default   Active   10.0.0.0/8        None
Default   Active   100.64.0.0/10     None
Default   Active   192.168.0.0/16    None
</pre>


### Firewall configs
<pre lang= >
<b>Delete default security config</b>
delete security

<b>Ensure firewalls have ssh service running (important since it is how the probe health checks the firewalls)
set system services ssh

<b>Interface configuration</b>
set interfaces ge-0/0/0 description UNTRUST
set interfaces ge-0/0/0 unit 0 family inet dhcp
set interfaces ge-0/0/1 description TRUST
set interfaces ge-0/0/1 unit 0 family inet dhcp
set interfaces fxp0 unit 0 family inet dhcp

<b>Security zones</b>
set security zones security-zone TRUST address-book address 10.80.99.10/32 10.80.99.10/32
set security zones security-zone TRUST address-book address 10.80.99.0/24 10.80.99.0/24
set security zones security-zone TRUST interfaces ge-0/0/1.0 host-inbound-traffic system-services all
set security zones security-zone TRUST interfaces ge-0/0/1.0 host-inbound-traffic protocols all
set security zones security-zone UNTRUST interfaces ge-0/0/0.0 host-inbound-traffic system-services dhcp
set security zones security-zone UNTRUST interfaces ge-0/0/0.0 host-inbound-traffic system-services ssh

<b>SNAT and DNAT configuration</b>
SNAT TO Internet
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK from zone TRUST
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK to zone UNTRUST
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK rule SNAT-R1 match source-address 10.80.99.0/24
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK rule SNAT-R1 then source-nat interface
SNAT to VNETs
set security nat source rule-set SNAT-TO-VNETS from zone UNTRUST
set security nat source rule-set SNAT-TO-VNETS to zone TRUST
set security nat source rule-set SNAT-TO-VNETS rule SNAT-R1-VNET match source-address 0.0.0.0/0
set security nat source rule-set SNAT-TO-VNETS rule SNAT-R1-VNET then source-nat interface
DNAT to web server
set security nat destination pool DST-NAT-POOL-1 description "Web server"
set security nat destination pool DST-NAT-POOL-1 address 10.80.99.10/32
set security nat destination rule-set DST-RS1 from zone UNTRUST
set security nat destination rule-set DST-RS1 rule DST-R1 match destination-address 0.0.0.0/0
set security nat destination rule-set DST-RS1 rule DST-R1 match destination-port 80
set security nat destination rule-set DST-RS1 rule DST-R1 then destination-nat pool DST-NAT-POOL-1

<b>Route policy for route leaking</b>
set policy-options prefix-list T-ALLOW-PREFIXES 0.0.0.0/0
set policy-options prefix-list U-ALLOW-PREFIXES 10.80.99.0/24
set policy-options policy-statement IMP-TRUST term 1 from prefix-list T-ALLOW-PREFIXES
set policy-options policy-statement IMP-TRUST term 1 then accept
set policy-options policy-statement IMP-TRUST term DENY-ALL then reject
set policy-options policy-statement IMP-UNTRUST term 1 from prefix-list U-ALLOW-PREFIXES
set policy-options policy-statement IMP-UNTRUST term 1 then accept
set policy-options policy-statement IMP-UNTRUST term DENY-ALL then reject

<b>Since we have a public and and internal load balancer, we have to configure 2 x virtual routers (L3 tables) to ensure the load balancer probes are routed out their specific ingress interfaces</b>

<b>Configuring routing instances</b>
set routing-instances VR-TRUST instance-type virtual-router
set routing-instances VR-TRUST interface ge-0/0/1.0
set routing-instances VR-TRUST routing-options static route 10.80.99.0/24 next-hop 10.0.1.1
set routing-instances VR-TRUST routing-options static route 168.63.129.16/32 next-hop 10.0.1.1
set routing-instances VR-TRUST routing-options static rib-group T-U-ROUTES-LEAK

set routing-instances VR-UNTRUST instance-type virtual-router
set routing-instances VR-UNTRUST interface ge-0/0/0.0
set routing-instances VR-UNTRUST routing-options static rib-group U-T-ROUTES-LEAK
set routing-instances VR-UNTRUST routing-options static route 0.0.0.0/0 next-hop 10.0.0.1

<b>In Junos route leaking requires the configuration of RIB-GROUPS (tells which route table to leak to where)</b>
set routing-options rib-groups U-T-ROUTES-LEAK import-rib VR-UNTRUST.inet.0
set routing-options rib-groups U-T-ROUTES-LEAK import-rib VR-TRUST.inet.0
set routing-options rib-groups U-T-ROUTES-LEAK import-policy IMP-TRUST
set routing-options rib-groups T-U-ROUTES-LEAK import-rib VR-TRUST.inet.0
set routing-options rib-groups T-U-ROUTES-LEAK import-rib VR-UNTRUST.inet.0
set routing-options rib-groups T-U-ROUTES-LEAK import-policy IMP-UNTRUST

<b>Security poilicies
set security policies from-zone TRUST to-zone UNTRUST policy TRUST-TO-UNTRUST match source-address 10.80.99.0/24
set security policies from-zone TRUST to-zone UNTRUST policy TRUST-TO-UNTRUST match destination-address any
set security policies from-zone TRUST to-zone UNTRUST policy TRUST-TO-UNTRUST match application any
set security policies from-zone TRUST to-zone UNTRUST policy TRUST-TO-UNTRUST then permit
set security policies from-zone TRUST to-zone UNTRUST policy TRUST-TO-UNTRUST then log session-init
set security policies from-zone TRUST to-zone UNTRUST policy TRUST-TO-UNTRUST then log session-close

set security policies from-zone UNTRUST to-zone TRUST policy DST-TO-WEB-TEST match source-address any
set security policies from-zone UNTRUST to-zone TRUST policy DST-TO-WEB-TEST match destination-address 10.80.99.10/32
set security policies from-zone UNTRUST to-zone TRUST policy DST-TO-WEB-TEST match application junos-http
set security policies from-zone UNTRUST to-zone TRUST policy DST-TO-WEB-TEST then permit
set security policies from-zone UNTRUST to-zone TRUST policy DST-TO-WEB-TEST then log session-init
set security policies from-zone UNTRUST to-zone TRUST policy DST-TO-WEB-TEST then log session-close

set security policies from-zone TRUST to-zone TRUST policy TRUST-TO-TRUST match source-address any
set security policies from-zone TRUST to-zone TRUST policy TRUST-TO-TRUST match destination-address any
set security policies from-zone TRUST to-zone TRUST policy TRUST-TO-TRUST match application any
set security policies from-zone TRUST to-zone TRUST policy TRUST-TO-TRUST then permit
set security policies from-zone TRUST to-zone TRUST policy TRUST-TO-TRUST then log session-init
set security policies from-zone TRUST to-zone TRUST policy TRUST-TO-TRUST then log session-close
</pre>

### After configuring the firewalls, you should be able to connect to the web server through the public LB IP address

<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/2_FW_NVA_HA_%2B_Az_Pub_%2B_Int_LB/apache2.png)</kbd>

Complete firewall configuration is attached to the lab folder.


### Lab Verification
### Check the firewall session table to ensure the load balancer health checks are being received from both public and internal load balancers


### View of the vSRX session table
<pre lang= >
*Health probe session shows the Azure probe source address destined to 10.0.0.4 (vSRX UNTRUST vNIC IP)
<b>show security flow session</b> 
Session ID: 111891, Policy name: self-traffic-policy/1, Timeout: 1798, Valid
<b>Incoming connection</b>In: <b>168.63.129.16/57166</b> --> 10.0.0.4/22;tcp, Conn Tag: 0x0, If: ge-0/0/0.0, Pkts: 3, Bytes: 132, 
<b>Outgoing connection</b>Out: 10.0.0.4/22 --> 168.63.129.16/57166;tcp, Conn Tag: 0x0, If: .local..7, Pkts: 2, Bytes: 112, 
Total sessions: 1

<b>This output shows the incoming HTTP connection to the LB Public IP</b>
*Since we have "Floating IP" enabled on the LB rule, the LB performs no destination translation

Session ID: 111929, Policy name: DST-TO-WEB-TEST/6, Timeout: 298, Valid
<b>Incoming connection</b>In: 71.59.10.124/19208 --> <b>52.xx.xx.xx</b>/80;tcp, Conn Tag: 0x0, If: ge-0/0/0.0, Pkts: 6, Bytes: 1055, 
<b>Outgoing connection</b>Out: 10.0.1.10/80 --> 10.0.1.4/28363;tcp, Conn Tag: 0x0, If: ge-0/0/1.0, Pkts: 8, Bytes: 7524, 
Total sessions: 2
</pre>
