Azurerm Terraform code to deploy Juniper vSRX Firewalls in Azure

1- Creates a resource_group
2- Creates a VNET w/ 10.100.0.0/16 address space
3- Creates a 3 x subnets in the VNET (untrust-10.100.0.0/24), trust-10.100.1.0/24, management-10.100.254.0/24)
4- Creates two public IPs for each vSRX fxp-0 and ge-0 interfaces
5- Creates vNICs - fxp0, ge0, ge1 for each vSRX
6- Defines a random_integer to leverage in other resources
7- Creates bootdiag storage account which allows you to serial_console into the vSRXs
8- Creates the 2 x byol vSRX firewalls running version 20.4.2 with interfaces fxp0 bound to management, ge0 bound to untrust, ge1 bound to trust

