### Automation script to import all Office365 IP addresses into a UDR with NextHop 'Internet'.
### The script shows what is possible in its simplest form, with more time and planning it can be more elaborate.

### Why did I publish this script? 
One use case which has become more common of late due to Covid-19, is in a Windows Virtual Desktop enviroment where customers are wanting to force tunnel traffic. This means on-prem advertises a default route into Azure, and all traffic is routed to on-prem. For security reasons, some Enterprises require force tunneling. This introduces some challenges with the desktops and also Office365.

In a Windows Virtual Desktop environment, routing Office365 traffic to on-premises will create unwanted latency and maybe even cause some services to fail. This issue is the main focus of this lab. Today, there are no Office365 service tags, nor do UDRs support service tags. To keep Office365 traffic local (or stay in Azure) can be done by automation scripts. This script would download all Office365 public IP addresses and port them into a UDR, which would then be applied to the desktop subnet. This is half of the challenge.  

The second half of this challange, is that Windows Virtual Desktop service requires that all desktops maintain a heartbeat/connection TCP 443 to the 'Broker' & 'Gateway' which is hosted in Azures ASE. Force tunneling would route these connections to on-prem introducing unwanted latency, or even stop working outright. This challenge can be addressed by routing traffic to either Azure firewall or a 3rd party NVA (VM) to make the routing decisions locally via the Azure fabric. 

###  Diagram below shows the Microsoft Windows Virtual Desktop environment. Control plane and Desktops (VNET).

<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/O365_IP_ADDRESSES_TO_UDR/wvd1.png)</kbd>


<pre lang= >
<b>What the Office365 script does in order:</b>
1- Downloads all Office 365 IP addresses and stores them in a variable ($flatIp4s)
2- Checks the specific VNET in question for existing subnets
3- Create the route table names for each subnet with the subnet name + '-RT'
4- Creates a new route table if one does not already exit
5- Creates the routing configuration. Route table names and prefixes based on variable $flatIp4s
6- Add the Microsoft Windows Activation (KMS) service route as well
7- Applies route table to the subnet
8- Updates the VNET with the new subnet and configuration
</pre>

### These are the results of the script:
### Since my subnet is called wvd, a route table was created 'wvd-RT'
<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/O365_IP_ADDRESSES_TO_UDR/img-1.png)</kbd>

### The new route table 'wvd-RT' has all of the Office365 routes populated with NextHop 'Internet'
<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/O365_IP_ADDRESSES_TO_UDR/img-2.png)</kbd>

### The new route table 'wvd-RT' was associated with the subnet 'wvd'
<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/O365_IP_ADDRESSES_TO_UDR/img-3.png)</kbd>

### This lab will be updated continually, as more features become available. Such as, UDR service tags ....
