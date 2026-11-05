# Deliberately INSECURE starting point. Scan it, fix the findings, re-scan.
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
  features {}
  subscription_id = var.subscription_id
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
  name                            = "sttflab${var.suffix}"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = true # weak: anonymous blob access allowed
  shared_access_key_enabled       = true # weak: account keys usable
  public_network_access_enabled   = true # weak: reachable from any network
}

resource "azurerm_network_security_group" "lab" {
  name                = "nsg-tf-lab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule { # weak: RDP open to the internet
    name                       = "allow-rdp-any"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_key_vault" "lab" {
  name                          = "kv-tflab-${var.suffix}"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false # weak: vault can be purged
  public_network_access_enabled = true  # weak: no network restriction
}
