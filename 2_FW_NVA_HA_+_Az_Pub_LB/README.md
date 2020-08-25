<p align="left">
<b>Azure Network Security Lab - In this lab we will deploy 2 firewalls (Juniper vSRX NVAs) in HA design with an Azure public load balancer. This desing provides high availability (HA) for Internet (public) inbound connections.</center></b>
<p align="left"><b>This design is vendor agonostic and can be inplemented identically across different NVAs.</p></b>
</p>
<p align="left"><b>Azure Configuration Elements</p></b>
<pre lang= >
* Create a resource group for all of the objects (LB, FW, VNET,...)
* Create a storagea account for boot diagnostics 
* Create a VNET w/ IP range
* Create 3 Subnets (Management, TRUST, and UNTRUST)
* Create public IP address objects for required elements
* Create nNICs for the firewalls (vSRX) and web server (Ubuntu + Apache)
* Create the virtual machines
* Configure the vSRX firewalls
* Create the Azure public load balancer
* Test Apache2 connectivity 
* Show the firewall session tables
</pre>

### Key details

The Azure public load balancer can be configured in two ways (This lab is focused on #2): 
<br>- Default rule config - Azure PLB will translate the destination IP address of incoming packets to that of one of the backend pool VMs.
<br>- Floating IP rule config - This setting will NOT translate the incoming packets destination IP. This means the packets preserve their original 5 tuples when load balanced between the back end firewalls.

### Design implications:
- When using the Azure Public LB default configuration, if you have multiple applications that are using the same destination port, you have to perform port translation. This is because backed pool VMs are limited to a single IP address. A NAT policy would need to be configured to perform the port translation. This can become cumbersome as you add more applications and create port translations. This is where Floating IP configuration helps.
- Floating IP configuration - With the type of LB rule in place, the LB will NOT perform destination NAT on the packets processed by the load balancer. The traffic will be load balanced and routed to the backend firewalls preserving the original 5 tuples. The firewall still requires a DNAT rule which translates the destination IP address (Public load balancer IP address) to the private side resource. However, this configuration overcomes the multiple applications and port numbers re-use issue from the 'default' config (applications utilizing the same destination port). This style of configuration also mitigates the potential management traffic conflicts with the probes. 
- Health check probes - There are 3 types of health probes you can use to check the health of the backend pool - TCP/HTTP/HTTPS - in this design, we are going to select TCP on port 22 (ssh) to the firewalls UNTRUST IP addresses. This is a simple TCP probe with a connection terminating 'four-way close' TCP handshake. The probe is looking for an ACK response from the firewall. I will be enabling the ssh service on the untrust interface of the firewall, where the probe will ingress. You should always secure the control plane by creating ACLs/Filters to only allow the required sources (that is beyond the scope of this document). Always keep in mind that probes are sent to the IP address of the firewalls, this means, when you are using the 'default' load balancer configuration, you may have conflicts with the firewall 'management' configurations (ssh etc...). 

### Topology Details - Simple Trust and Untrust topology. This lab is applicable, if the target backend VM was running on a peered spoke VNET (UDR required on spoke).

<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/2_FW_NVA_HA_%2B_Az_Pub_LB/topology1.png)</kbd>

### Elements required
<pre lang= >
  - Resource Group 
  - Azure public Load balancer
    - Public IP address
    - Backed Pools
    - Health Probes
    - Load Balancing Rules
  - 2 x Juniper vSRX NVA Firewalls - Each with:
    - vNIC1 - Mapped to management subnet
    - vNIC2 - Mapped to UNTRUST subnet
    - vNIC3 - Mapped to TRUST subnet
    - Destination NAT policies - For incoming applications
    - Source NAT policies - For flow affinity to backe ends
    - TRUST & UNTRUST security zones
    - Custom routing instance (Type virtual-router)
    - Secutity policies 
  - VNET
      - IP Range - 10.0.0.0/16
      - Management Subnet - MGMT 10.0.254.0/24
      - UNTRUST Subnet - O-UNTRUST 10.0.0.0/24
      - TRUST Subnet - O-TRUST 10.0.1.0/24
    - Ubuntu Virtual machine + Apache2
</pre>

### Create the Resource Group
<pre lang= >
az group create --name RG-PLB-TEST --location eastus --output table
</pre>
### Create a storage account for boot diagnosticsp
<pre lang= >
az storage account create -n mcbootdiag -g RG-PLB-TEST -l eastus --sku Standard_LRS
</pre>
### Create the HUB and a SPOKE VNET
<pre lang= >
az network vnet create --name HUB-VNET --resource-group RG-PLB-TEST --location eastus --address-prefix 10.0.0.0/16
az network vnet create --name SPOKE-VNET --resource-group RG-PLB-TEST --location eastus --address-prefix 10.80.0.0/16
</pre>

### Create the Subnets in HUB and SPOKE VNETs
<pre lang= >
az network vnet subnet create --vnet-name HUB-VNET --name MGMT --resource-group RG-PLB-TEST --address-prefixes 10.0.254.0/24 --output table
az network vnet subnet create --vnet-name HUB-VNET --name O-UNTRUST --resource-group RG-PLB-TEST --address-prefixes 10.0.0.0/24 --output table
az network vnet subnet create --vnet-name HUB-VNET --name O-TRUST --resource-group RG-PLB-TEST --address-prefixes 10.0.1.0/24 --output table
az network vnet subnet create --vnet-name SPOKE-VNET --name VMWORKLOADS --resource-group RG-PLB-TEST --address-prefixes 10.80.99.0/24 --output table
</pre>

### VNET Peer HUB and SPOKE VNETs
<pre lang= >
az network vnet peering create -g RG-PLB-TEST --name HUB-TO-SPOKE --vnet-name HUB-VNET --remote-vnet SPOKE-VNET --allow-forwarded-traffic --allow-vnet-access --output table
az network vnet peering create -g RG-PLB-TEST --name SPOKE-TO-HUB --vnet-name SPOKE-VNET --remote-vnet HUB-VNET --allow-forwarded-traffic --allow-vnet-access --output table
</pre>
### Create the Public IPs - When utilizing Public IPs with Standard SKU, an NSG is required on the Subnet/vNIC. Two public IPs will be created per Firewall NVA, and 1 for the Public LB. 1) fxp0 - management interface 2) ge0 - UNTRUST/Interface facing interface
<pre lang= >
<b>vSRX1</b>
az network public-ip create --name VSRX1-PIP-1 --allocation-method Static --resource-group RG-PLB-TEST --location eastus --sku Standard
az network public-ip create --name VSRX1-PIP-2 --allocation-method Static --resource-group RG-PLB-TEST --location eastus --sku Standard
<b>vSRX2</b>
az network public-ip create --name VSRX2-PIP-1 --allocation-method Static --resource-group RG-PLB-TEST --location eastus --sku Standard
az network public-ip create --name VSRX2-PIP-2 --allocation-method Static --resource-group RG-PLB-TEST --location eastus --sku Standard
<b>Az Load Balancer Public IP</b>
az network public-ip create --name AZ-PUB-LB-PIP --allocation-method Static --resource-group RG-PLB-TEST --location eastus --sku Standard
</pre>
### Create the vNICs
* fxp0 = Out of band management interface on vSRXs
<pre lang>
<b>VSRX1</b>
az network nic create --resource-group RG-PLB-TEST --location eastus --name VSRX1-fxp0 --vnet-name HUB-VNET --subnet MGMT --public-ip-address  VSRX1-PIP-1 --private-ip-address 10.0.254.4 
az network nic create --resource-group RG-PLB-TEST --location eastus --name VSRX1-ge0 --vnet-name HUB-VNET --subnet O-UNTRUST --public-ip-address  VSRX1-PIP-2 --private-ip-address 10.0.0.4 --ip-forwarding
az network nic create --resource-group RG-PLB-TEST --location eastus --name VSRX1-ge1 --vnet-name HUB-VNET --subnet O-TRUST --private-ip-address 10.0.1.4 --ip-forwarding
<b>VSRX2</b>
az network nic create --resource-group RG-PLB-TEST --location eastus --name VSRX2-fxp0 --vnet-name HUB-VNET --subnet MGMT --public-ip-address  VSRX2-PIP-1 --private-ip-address 10.0.254.5
az network nic create --resource-group RG-PLB-TEST --location eastus --name VSRX2-ge0 --vnet-name HUB-VNET --subnet O-UNTRUST --public-ip-address  VSRX2-PIP-2 --private-ip-address 10.0.0.5
az network nic create --resource-group RG-PLB-TEST --location eastus --name VSRX2-ge1 --vnet-name HUB-VNET --subnet O-TRUST --private-ip-address 10.0.1.5
<b>Web Server VM</b>
az network nic create --resource-group RG-PLB-TEST --location eastus --name WEB-eth0 --vnet-name SPOKE-VNET --subnet VMWORKLOADS --private-ip-address 10.80.99.10
</pre>
### Create NSGs - Since I selected to use 'Standard' SKU public IP addresses explicitly defined NSG is required
<pre lang=>
<b>Contral Plane NSG</b>
az network nsg create --resource-group RG-PLB-TEST --name CP-NSG --location eastus
az network nsg rule create -g RG-PLB-FW-LAB --nsg-name CP-NSG -n ALLOW-SSH --priority 300 --source-address-prefixes Internet --destination-address-prefixes 10.0254.0/24 --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow SSH to Management Subnet"
az network nsg rule create -g RG-PLB-FW-LAB --nsg-name CP-NSG -n ALLOW-ICMP --priority 301 --source-address-prefixes Internet --destination-address-prefixes 10.0.54.0/24 --destination-port-ranges * --protocol Icmp --description "Allow ICMP to FW OOB interface"
<b>Untrust Subnet NSG</b>
az network nsg create --resource-group RG-PLB-TEST --name UNTRUST-NSG --location eastus
az network nsg rule create -g RG-PLB-FW-LAB --nsg-name UNTRUST-NSG -n ALLOW-HTTP --priority 200 --source-address-prefixes * --source-port-ranges * --destination-address-prefixes * --destination-port-ranges 80 --access Allow --protocol Tcp --description "Allow HTTP to Untrust Subnet"
<b>Associate vNICs with corresponding NSGs</b>
az network nic update --resource-group RG-PLB-TEST --name VSRX1-fxp0 --network-security-group CP-NSG
az network nic update --resource-group RG-PLB-TEST --name VSRX2-fxp0 --network-security-group CP-NSG
az network nic update --resource-group RG-PLB-TEST --name VSRX1-ge0 --network-security-group UNTRUST-NSG
az network nic update --resource-group RG-PLB-TEST --name VSRX2-ge0 --network-security-group UNTRUST-NSG
</pre>

### Up to this point, we have created the following topology
<pre lang=>
1- Created HUB & SPOKE VNET
2- Created TRUST, UNTRUST, and MGMT (firewall maangement) subnets
3- Created the Public IP addresses for the firewalls and the load balancer
4- Created the vNICs for the firewalls, and the web server
5- Created the NSGs
</pre>

<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/2_FW_NVA_HA_%2B_Az_Pub_LB/topology2.png)
</kbd>

### Create the vSRX firewall VMs
<pre lang=>
<b>First - Accept the Juniper Networks license agreement</b>
<b>In PowerShell</b>
Get-AzureRmMarketplaceTerms -Publisher juniper-networks -Product vsrx-next-generation-firewall -Name vsrx-byol-azure-image | Set-AzureRmMarketplaceTerms -Accept
<b>VSRX1</b>
az vm create --resource-group RG-PLB-TEST --location eastus --name VSRX1 --size Standard_DS3_v2 --nics VSRX1-fxp0 VSRX1-ge0 VSRX1-ge1 --image juniper-networks:vsrx-next-generation-firewall:vsrx-byol-azure-image:19.2.1 --admin-username lab-user --admin-password AzLabPass1234 --boot-diagnostics-storage mcbootdiag --no-wait
<b>VSRX2</b>
az vm create --resource-group RG-PLB-TEST --location eastus --name VSRX2 --size Standard_DS3_v2 --nics VSRX2-fxp0 VSRX2-ge0 VSRX2-ge1 --image juniper-networks:vsrx-next-generation-firewall:vsrx-byol-azure-image:19.2.1 --admin-username lab-user --admin-password AzLabPass1234 --boot-diagnostics-storage mcbootdiag --no-wait
</pre>
### Create a test Web server VM
<pre lang=>
az vm create -n WEB-SERVER -g RG-PLB-TEST --image UbuntuLTS --admin-username lab-user --admin-password AzLabPass1234 --nics WEB-eth0 --boot-diagnostics-storage mcbootdiag --no-wait
<b>Once the VM is up and running, run the following to update and install apache2:</b>
1- sudo apt update
2- sudo apt upgrade -y
3- sudo apt install apache2 -y
</pre>
### Create the Azure Public load balancer
<pre lang= >
<b>Create the LB</b>
az network lb create --resource-group RG-PLB-TEST --name AZ-PUB-LB --sku Standard --public-ip-address AZ-PUB-LB-PIP --no-wait
<b>Create the backend pool</b>
az network LB address-pool create --lb-name AZ-PUB-LB --name PLB1-BEPOOL --resource-group RG-PLB-TEST
<b>Create the probe</b>
az network LB probe create --resource-group RG-PLB-TEST --name BE-PROBE1 --protocol tcp --port 22 --interval 30 --threshold 2 --lb-name AZ-PUB-LB
<b>Create a LB rule</b>
az network lb rule create --resource-group RG-PLB-TEST --name LB-RULE-1 --backend-pool-name PLB1-BEPOOL --probe-name BE-PROBE1 --protocol Tcp --frontend-port 80 --backend-port 80 --lb-name AZ-PUB-LB --floating-ip true --output table
<b>Add the VSRX1-ge0 & VSRX2-ge0 vNICs to the LB backend pool</b>
az network nic ip-config update -g RG-PLB-TEST --nic-name VSRX1-ge0 -n ipconfig1 --lb-address-pool PLB1-BEPOOL --vnet-name hub-vnet --subnet O-UNTRUST --lb-name AZ-PUB-LB
az network nic ip-config update -g RG-PLB-TEST --nic-name VSRX2-ge0 -n ipconfig1 --lb-address-pool PLB1-BEPOOL --vnet-name hub-vnet --subnet O-UNTRUST --lb-name AZ-PUB-LB
</pre>

<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/2_FW_NVA_HA_%2B_Az_Pub_LB/topology1.png)</kbd>

### Get a list of the public IPs, or specific instances public IPs
<pre lang= >
az network public-ip list --output table
<b>Output</b>
Name           ResourceGroup    Location    Zones    Address         AddressVersion    AllocationMethod    IdleTimeoutInMinutes    ProvisioningState
-------------  ---------------  ----------  -------  --------------  ----------------  ------------------  ----------------------  -------------------
AZ-PUB-LB-PIP  RG-PLB-TEST      eastus               52.xx.xx.xx    IPv4              Static              4                       Succeeded
VSRX1-PIP-1    RG-PLB-TEST      eastus               104.xx.xx.xx   IPv4              Static              4                       Succeeded
VSRX1-PIP-2    RG-PLB-TEST      eastus               52.xx.xx.xx    IPv4              Static              4                       Succeeded
VSRX2-PIP-1    RG-PLB-TEST      eastus               104.xx.xx.xx   IPv4              Static              4                       Succeeded
VSRX2-PIP-2    RG-PLB-TEST      eastus               52.xx.xx.xx    IPv4              Static              4                       Succeeded
<b>For specific instance</b>
az network public-ip show -g RG-PLB-TEST --name VSRX1-PIP-1 --output table
<b>Output</b>
Name         ResourceGroup    Location    Zones    Address        AddressVersion    AllocationMethod    IdleTimeoutInMinutes    ProvisioningState
-----------  ---------------  ----------  -------  -------------  ----------------  ------------------  ----------------------  -------------------
VSRX1-PIP-1  RG-PLB-TEST      eastus               <b>104.xx.xx.xx</b>  IPv4              Static              4                       Succeeded

az network public-ip show -g RG-PLB-TEST --name VSRX2-PIP-1 --output table
<b>Output</b>
Name         ResourceGroup    Location    Zones    Address        AddressVersion    AllocationMethod    IdleTimeoutInMinutes    ProvisioningState
-----------  ---------------  ----------  -------  -------------  ----------------  ------------------  ----------------------  -------------------
VSRX2-PIP-1  RG-PLB-TEST      eastus               <b>104.xx.xx.xx</b>  IPv4              Static              4                       Succeeded
</pre>
### To ssh and manage firewall VMs
<pre lang= >
<b>ssh lab-user@104.xx.xx.xx</b>
<b>Output</b>
The authenticity of host '104.xx.xx.xx (104.xx.xx.xx)' can't be established.
RSA key fingerprint is SHA256:<scrubbed info>.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '104.45.173.74' (RSA) to the list of known hosts.
Password:
--- JUNOS 19.<scrubbed> Kernel 64-bit XEN JNPR-<scrubbed info>_buil
lab-user@VSRX1> 

<b>ssh lab-user@104.xx.xx.xx</b>
<b>Output</b>
The authenticity of host '104.xx.xx.xx (104.xx.xx.xx)' can't be established.
RSA key fingerprint is SHA256:<scrubbed info>.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '104.xx.xx.xx' (RSA) to the list of known hosts.
Password:
--- JUNOS 19.<scrubbed> Kernel 64-bit XEN JNPR-<scrubbed info>_buil
lab-user@VSRX2> 
</pre>
### vSRX configuraitons- Both vSRX will have identical configs
<pre lang= >
<b>Delete default security config</b>
delete security
<b>Interfaces configuration</b>
set interfaces ge-0/0/0 description UNTRUST
set interfaces ge-0/0/0 unit 0 family inet dhcp
set interfaces ge-0/0/1 description TRUST
set interfaces ge-0/0/1 unit 0 family inet dhcp
set interfaces fxp0 unit 0 family inet dhcp

<b>Routing instance configuration</b>
set routing-instances VR-1 instance-type virtual-router
set routing-instances VR-1 routing-options static route 168.63.129.16/32 next-hop 10.0.0.1  >><b>LB probe static route</b>
set routing-instances VR-1 routing-options static route 0.0.0.0/0 next-hop 10.0.0.1 >><b>Default route to internet</b>
set routing-instances VR-1 interface ge-0/0/0.0
set routing-instances VR-1 interface ge-0/0/1.0
<b>Security zone configuraiton</b>
delete security
set security zones security-zone TRUST address-book address 10.0.1.10/32 10.0.1.10/32 >><b>Address book entry of web server</b>
set security zones security-zone TRUST interfaces ge-0/0/1.0 host-inbound-traffic system-services all
set security zones security-zone TRUST interfaces ge-0/0/1.0 host-inbound-traffic protocols all
set security zones security-zone UNTRUST interfaces ge-0/0/0.0 host-inbound-traffic system-services dhcp
set security zones security-zone UNTRUST interfaces ge-0/0/0.0 host-inbound-traffic system-services ssh
<b>Destination NAT (DNAT)</b>
set security nat destination pool DST-NAT-POOL-1 address 10.0.1.10/32 >><b>IP address of Web server</b>
set security nat destination rule-set DST-RS1 from interface ge-0/0/0.0 >><b>Ingress interface of traffic</b>
set security nat destination rule-set DST-RS1 rule DST-R1 match destination-address 52.xx.xx.xx/32 >><b>Public IP of LB</b>
set security nat destination rule-set DST-RS1 rule DST-R1 then destination-nat pool DST-NAT-POOL-1
<b>Source NAT (SNAT) for return flow affinity</b>
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK from zone UNTRUST
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK to zone TRUST
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK rule SNAT-R1 match destination-address 10.0.1.0/24
set security nat source rule-set SNAT-FOR-DNAT-TO-WORK rule SNAT-R1 then source-nat interface
<b>Security policies to allow incoming HTTP traffic to the Web server, also TRUST to TRUST for internal hairpin traffic</b>
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

<b>Static route to VMWORKLOAD VNET</b>
set routing-instances VR-1 routing-options static route 10.80.99.0/24 next-hop 10.0.1.1
</pre>

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
### Test connection to the backend Web server via the Public LB IP address - It works ;) you can shut down a vSRX and traffic will continue to flow

<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/2_FW_NVA_HA_%2B_Az_Pub_LB/apache.png)</kbd>

At this point, you have an Azure Standard SKU public load balancer. This load balancer will forward traffic to two firewalls (vSRXs) network virtual appliances (NVAs). 

<b>Our next lab covers 2 firewalls sandwiched between two loab balancers (Public and Internal LB)</b><a href="https://github.com/ManCalAzure/AzureLabs/tree/master/AzureSpecificDesigns/2_FW_NVA_HA_+_Az_Pub_+_Int_LB/README.md"> here</a>.<br /></p>
