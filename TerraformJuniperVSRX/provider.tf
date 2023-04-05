provider "azurerm" {
  version = "3.47.0"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
    tenant_id       = "<Directory tenant ID>"
    subscription_id = "<Azure subscription ID>"
    client_id       = "<Application (client) ID>"
    client_secret   = "<Client ecret ID>"
}
