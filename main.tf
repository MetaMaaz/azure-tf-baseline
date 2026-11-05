# Hardened version. Every Checkov finding is either fixed or skipped with a reason.
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    storage {
      # Public network access is off, so Terraform must not call the blob/queue
      # endpoints from outside. Management plane (ARM) only.
      data_plane_available = false
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true # shared keys are off, so use Entra auth
}

variable "subscription_id" { type = string }
variable "suffix" {
  type        = string
  description = "Lowercase letters/digits, makes names globally unique, e.g. mh2905"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "lab" {
  name     = "rg-tf-lab"
  location = "uksouth"
}

resource "azurerm_storage_account" "lab" {
  #checkov:skip=CKV_AZURE_33:No queues in this account, so queue logging has nothing to log.
  #checkov:skip=CKV2_AZURE_33:Lab. Public network access is disabled instead; private endpoint needs a VNet, out of scope.
  #checkov:skip=CKV_AZURE_206:Lab data. ZRS covers a zone outage; geo-redundant copies roughly double the cost for throwaway data.
  #checkov:skip=CKV2_AZURE_1:Lab data. Microsoft-managed keys accepted; CMK adds a Key Vault key and identity to run.
  name                            = "sttflab${var.suffix}"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS" # was LRS: three zones instead of one datacentre
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false # no anonymous blob access
  shared_access_key_enabled       = false # Entra auth only, no account keys
  default_to_oauth_authentication = true
  public_network_access_enabled   = false # not reachable from the internet

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "01.00:00:00" # any SAS must expire within a day
  }
}

# RDP rule removed. Admin access goes through Bastion or JIT, not an open port.
resource "azurerm_network_security_group" "lab" {
  name                = "nsg-tf-lab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

resource "azurerm_key_vault" "lab" {
  #checkov:skip=CKV2_AZURE_32:Lab. Public network access is disabled instead; private endpoint needs a VNet, out of scope.
  name                          = "kv-tflab-${var.suffix}"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true # Azure RBAC, not access policies
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true # deleted vault cannot be purged during retention
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}
