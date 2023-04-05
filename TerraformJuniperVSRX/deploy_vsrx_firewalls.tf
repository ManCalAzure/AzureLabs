##Deploy VSRX Firewalls####################
#Create Resource Group in Azure
resource "azurerm_resource_group" "rg2" {
  name     = var.resource_group_2
  location = var.location_1
}  

##Create VNET#####################
resource "azurerm_virtual_network" "vsrx_vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name
  address_space       = ["10.100.0.0/16"]
  #dns_servers         = ["10.0.0.4", "10.0.0.5"]
}

###Create Subnet####################
resource "azurerm_subnet" "vsrx_untrust" {
  name                 = "untrust"
  resource_group_name = azurerm_resource_group.rg2.name
  virtual_network_name = azurerm_virtual_network.vsrx_vnet.name
  address_prefixes     = ["10.100.0.0/24"]
}

resource "azurerm_subnet" "vsrx_trust" {
  name                 = "trust"
  resource_group_name = azurerm_resource_group.rg2.name
  virtual_network_name = azurerm_virtual_network.vsrx_vnet.name
  address_prefixes     = ["10.100.1.0/24"]
}

resource "azurerm_subnet" "vsrx_management" {
  name                 = "management"
  resource_group_name = azurerm_resource_group.rg2.name
  virtual_network_name = azurerm_virtual_network.vsrx_vnet.name
  address_prefixes     = ["10.100.254.0/24"]
}

###Create VSRX public IP addresses####################
resource "azurerm_public_ip" "generate_fxp0_pips" {
  count               = 2
  name                = "vsrx${count.index}-fxp0-pip"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "generate_ge0_pips" {
  count               = 2
  name                = "vsrx${count.index}-ge0-pip"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name
  allocation_method   = "Static"
}

###Create vNICs####################
resource "azurerm_network_interface" "vsrx_fxp0_vnics" {
  count               = 2
  name                = "vsrx${count.index}-fxp0-vnic"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name

  ip_configuration {
    name                          = "ifconfig"
    subnet_id                     = azurerm_subnet.vsrx_management.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.generate_fxp0_pips[count.index].id
  }
}

resource "azurerm_network_interface" "vsrx_ge0_vnics" {
  count               = 2
  name                = "vsrx${count.index}-ge0-vnic"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name

  ip_configuration {
    name                          = "ipconfig${count.index}"
    subnet_id                     = azurerm_subnet.vsrx_untrust.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.generate_ge0_pips[count.index].id
  }
}

resource "azurerm_network_interface" "vsrx_ge1_vnics" {
  count               = 2
  name                = "vsrx${count.index}-ge1-vnic"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name

  ip_configuration {
    name                          = "ipconfig${count.index}"
    subnet_id                     = azurerm_subnet.vsrx_trust.id
    private_ip_address_allocation = "Dynamic"
#    public_ip_address_id          = azurerm_public_ip.generate_ge0_pips[count.index].id
  }
}

# Define a random integer for naming resources
resource "random_integer" "random_int" {
  min = 1000
  max = 9999
}

# Storage account resource for boot diagnostics
resource "azurerm_storage_account" "sa" {
  name                     = "fwbootdiag${random_integer.random_int.result}"
  resource_group_name      = azurerm_resource_group.rg2.name
  location                 = azurerm_resource_group.rg2.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

#############################Create Firewalls#############################
resource "azurerm_linux_virtual_machine" "nva_vm" {
  count               = 2
  name                = "nva-${random_integer.random_int.result}-${count.index}"
  resource_group_name = azurerm_resource_group.rg2.name
  location            = azurerm_resource_group.rg2.location
  size                = "Standard_D4_v3"
  disable_password_authentication = false
  admin_username      = "<set a username>"
  admin_password      = "<set a password>"   # set the admin password for the NVA
  network_interface_ids = [
    azurerm_network_interface.vsrx_fxp0_vnics.*.id[count.index],
    azurerm_network_interface.vsrx_ge0_vnics.*.id[count.index],
    azurerm_network_interface.vsrx_ge1_vnics.*.id[count.index]
  ]
#  custom_data           = base64encode(templatefile("./custom-data.txt", "test=test"))

  os_disk {
    name              	 = "nva-os-disk-${count.index}"
    caching           	 = "ReadWrite"
#    create_option     	 = "FromImage"
#    managed_disk_type 	 = "Standard_LRS"
    storage_account_type = "Standard_LRS"
  }
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.sa.primary_blob_endpoint
  }  

 # Define the VM image
  source_image_reference {
    publisher = "juniper-networks"
    offer     = "vsrx-next-generation-firewall-payg"
    sku       = "vsrx-azure-image-byol"
    version   = "20.4.2"
  }

  plan {
    name      = "vsrx-azure-image-byol"
    publisher = "juniper-networks"
    product   = "vsrx-next-generation-firewall-payg"
  }
  
}




