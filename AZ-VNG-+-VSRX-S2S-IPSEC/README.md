### IPSec VPN Lab - Azure Virtual Network Gateway site-to-site IPSec VPN with Juniper vSRX

### Steps
<pre lang= >
<b>1-</b> Create a resource group
<b>2-</b> Create the VNET with GatewaySubnet
<b>3-</b> Create a public IP for the VNG
<b>4-</b> Create the VNG with the following parameters:
  - Sku = VpnGw1
  - Gateway-type = Vpn
  - vpn-type = RouteBased
  - ASN = 65002
  - bgp-peering-address = 10.225.254.254 (GatewaySubnet highest IP)
<b>5-</b> Create the 'Local Network Gateway' - remote firewall settings
  - gateway-ip-address = 71.xx.xx.xx.xx
  - asn = 65001 
  - bgp-peering-address = 10.250.250.250
  - local-address-prefixes = 10.250.0.0/16
<b>6-</b> Create the connection to tie the VNG and remote gateway in IPSec
  - vnet-gateway1 = GW-TEST-VNG
  - local-gateway2 = LGW-1
  - enable-bgp
</pre>
<pre lang= >
<b>Create Resource group</b>
az group create --name RG-GW-TEST --location westus

<b>Create VNET</b>
az network vnet create -n GW-TEST  -g RG-GW-TEST -l westus --address-prefix 10.225.0.0/16  --subnet-name <b>GatewaySubnet</b> --subnet-prefix 10.225.254.0/24

<b>Create VNG PIP</b>
az network public-ip create -n GW-TEST-PIP -g RG-GW-TEST --allocation-method Dynamic

<b>Create VPN GW - (for bgp peer address if you are setting this yourself grab the highest IP in the GatewaySubnet range .254)</b>
az network vnet-gateway create -n GW-TEST-VNG -l westus --public-ip-address GW-TEST-PIP -g RG-GW-TEST --vnet GW-TEST --gateway-type Vpn --sku VpnGw1 --vpn-type RouteBased --asn 65002 --bgp-peering-address 10.225.254.254 --no-wait

<b>Create the Local Network Gateway (Remote firewall config): gw ip:71.59.10.124,remote asn 65001, peer ip 10.250.250.250, remote LAN 10.250.0.0/16</b>
az network local-gateway create --gateway-ip-address 71.59.10.124 -g RG-GW-TEST -n LGW-1 --asn 65001 --bgp-peering-address 10.250.250.250 --local-address-prefixes 10.250.0.0/16

<b>Create the Connection</b>
az network vpn-connection create -g RG-GW-TEST -n CONNECITON-1 --vnet-gateway1 GW-TEST-VNG --local-gateway2 LGW-1 --enable-bgp --location westus --shared-key AzLabPass123
</pre>
<pre lang= >
<b>Azure VNG details Portal view</b>
</pre>
<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/AZ-VNG-%2B-VSRX-S2S-IPSEC/gw-view.png)</kbd>


### Juniper SRX Configuration
<pre lang= >
<b>Phase 1 - IKE Configuraiton</b>
set security ike proposal AZ-P1 authentication-method pre-shared-keys
set security ike proposal AZ-P1 dh-group group2
set security ike proposal AZ-P1 authentication-algorithm sha1
set security ike proposal AZ-P1 encryption-algorithm aes-256-cbc
set security ike proposal AZ-P1 lifetime-seconds 28800
set security ike policy AZ-POL1 mode main
set security ike policy AZ-POL1 proposals AZ-P1
set security ike policy AZ-POL1 pre-shared-key ascii-text <b><the preshared key/password></b>
set security ike gateway AZ-GW1 ike-policy AZ-POL1
set security ike gateway AZ-GW1 address 40.xx.xx.xx <b>(Azure VNG public IP address)</b>
set security ike gateway AZ-GW1 dead-peer-detection interval 10
set security ike gateway AZ-GW1 dead-peer-detection threshold 5
set security ike gateway AZ-GW1 local-identity inet 71.59.10.124 <b>====> Local public IP address of FW</b>
set security ike gateway AZ-GW1 external-interface ge-0/0/0.0 <b>====>Untrust Interface of FW</b>
set security ike gateway AZ-GW1 version v2-only

<b>Phase 2 - IPSec Configuraiton</b>
set security ipsec proposal AZ-IPSEC-P2 protocol esp
set security ipsec proposal AZ-IPSEC-P2 authentication-algorithm hmac-sha-256-128
set security ipsec proposal AZ-IPSEC-P2 encryption-algorithm aes-256-cbc
set security ipsec proposal AZ-IPSEC-P2 lifetime-seconds 3600
set security ipsec policy IPSEC-POL-1 proposals AZ-IPSEC-P2
set security ipsec vpn VPN bind-interface st0.0 <b>====> Tunnel Interface/VTI</b>
set security ipsec vpn VPN ike gateway AZ-GW1
set security ipsec vpn VPN ike proxy-identity local 0.0.0.0/0
set security ipsec vpn VPN ike proxy-identity remote 0.0.0.0/0
set security ipsec vpn VPN ike proxy-identity service any
set security ipsec vpn VPN ike ipsec-policy IPSEC-POL-1
set security ipsec vpn VPN establish-tunnels immediately

<b>BGP Configuration</b>
set protocols bgp group TO-AZURE type external
set protocols bgp group TO-AZURE <b>multihop</b> ttl 2 <b>====> Important since BGP neighbor is not directly connected</b>
set protocols bgp group TO-AZURE neighbor 10.225.254.254 peer-as 65002 <b>=====>Azure VNG peering IP + peer AS</b>

<b>Other relevant configuraiton</b>
set interfaces lo0 unit 0 family inet address 10.250.250.250/32 <b>====>Local peering loopback</b>
set interfaces st0 unit 0 family inet 
set routing-options static route 10.225.254.254/32 next-hop st0.0 <b>====>Need to set static to remote VNG BGP neighbor</b>

<b>VPN security zone (this can also work in UNTRUST zone)</b>
set security zones security-zone VPN-ZONE address-book address 10.250.0.0/16 10.250.0.0/16 <b>====>Address book entries</b>
set security zones security-zone VPN-ZONE address-book address 10.225.0.0/16 10.225.0.0/16 <b>====>Address book entries</b>
set security zones security-zone VPN-ZONE interfaces st0.0 <b>====>Tunnel interface bound to VPN-ZONE</b>

<b>security policies</b>
set security policies from-zone TRUST to-zone VPN-ZONE policy TRUST-VPN-ZONE match source-address 10.250.0.0/16
set security policies from-zone TRUST to-zone VPN-ZONE policy TRUST-VPN-ZONE match destination-address 10.225.0.0/16
set security policies from-zone TRUST to-zone VPN-ZONE policy TRUST-VPN-ZONE match application any
set security policies from-zone TRUST to-zone VPN-ZONE policy TRUST-VPN-ZONE then permit

set security policies from-zone VPN-ZONE to-zone TRUST policy VPN-ZONE-TRUST match source-address 10.225.0.0/16
set security policies from-zone VPN-ZONE to-zone TRUST policy VPN-ZONE-TRUST match destination-address 10.250.0.0/16
set security policies from-zone VPN-ZONE to-zone TRUST policy VPN-ZONE-TRUST match application any
set security policies from-zone VPN-ZONE to-zone TRUST policy VPN-ZONE-TRUST then permit
</pre>

<b>Portal verification that tunnel is connected</b>
<kbd>![alt text](https://github.com/ManCalAzure/AzureLabs/blob/master/AZ-VNG-%2B-VSRX-S2S-IPSEC/portal-up.png)</kbd>

<b>SRX on-prem tunnel verification</b>
<pre lang= >
<b>show security ike security associations</b>
<div class="boxed">
Index   State  Initiator cookie  Responder cookie  Mode           Remote Address   
3887757 <b>UP</b>     872c2bf09817d79f  09cf62ffc0c80c21  IKEv2          40.xx.xx.xx
</div>
<b>show security ipsec security associations</b>
<div class="boxed">
  Total active tunnels: 1     Total Ipsec sas: 1
  ID    Algorithm       SPI      Life:sec/kb  Mon lsys Port  Gateway   
  <131073 ESP:aes-cbc-256/sha256 3cd26cfe 1303/ unlim - root 500 40.xx.xx.xx 
  >131073 ESP:aes-cbc-256/sha256 964dac8e 1303/ unlim - root 500 40.xx.xx.xx 
</div>
<b>show interface terse st0</b>
<div class="boxed">
Interface               Admin Link Proto    Local                 Remote
st0                     <b>up</b>    <b>up</b>
st0.0                   <b>up</b>    <b>up</b>   inet 
</div>
</pre>
<pre lang= >
<b>show bgp summary</b>
<div class="boxed">
Threading mode: BGP I/O
Groups: 1 Peers: 1 Down peers: 0
Table          Tot Paths  Act Paths Suppressed    History Damp State    Pending
inet.0               
                       1          1          0          0          0          0
Peer                     AS      InPkt     OutPkt    OutQ   Flaps Last Up/Dwn State|#Active/Received/Accepted/Damped...
<b>10.225.254.254</b>        <b>65002</b>         99         96       0       1       42:37 1/1/1/0              0/0/0/0
</div>
</pre>
<pre lang= >
<b>show route receive-protocol bgp 10.225.254.254</b> ====> BGP routes received from VNG
<div class="boxed">
inet.0: 14 destinations, 14 routes (14 active, 0 holddown, 0 hidden)
  Prefix                  Nexthop              MED     Lclpref    AS path
* <b>10.225.0.0/16</b>           <b>10.225.254.254</b>                          <b>65002</b> I
</div>
</pre>

<b>You can ping the BGP neighbor VNG IP</b>
<pre lang= >
<div class="boxed">
ping 10.225.254.254 
PING 10.225.254.254 (10.225.254.254): 56 data bytes
64 bytes from 10.225.254.254: icmp_seq=0 ttl=127 time=67.500 ms
64 bytes from 10.225.254.254: icmp_seq=1 ttl=127 time=66.605 ms
64 bytes from 10.225.254.254: icmp_seq=2 ttl=127 time=65.792 ms
64 bytes from 10.225.254.254: icmp_seq=3 ttl=127 time=66.107 ms
</div>
</pre>
