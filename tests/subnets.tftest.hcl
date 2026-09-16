mock_provider "azurerm" {
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/app"
    }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-app"
    }
  }
  mock_resource "azurerm_route_table" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/routeTables/rt-app"
    }
  }
}

variables {
  resource_group_name  = "rg-test"
  location             = "uksouth"
  virtual_network_name = "vnet-test"
  subnets = {
    app = { address_prefixes = ["10.20.1.0/24"] }
  }
}

run "private_defaults_and_reserved_names" {
  command = plan

  variables {
    subnets = {
      app                           = { address_prefixes = ["10.20.1.0/24"] }
      GatewaySubnet                 = { address_prefixes = ["10.20.2.0/27"] }
      AzureFirewallSubnet           = { address_prefixes = ["10.20.3.0/26"] }
      AzureFirewallManagementSubnet = { address_prefixes = ["10.20.4.0/26"] }
      AzureBastionSubnet            = { address_prefixes = ["10.20.5.0/26"] }
    }
  }

  assert {
    condition     = alltrue([for subnet in azurerm_subnet.this : !subnet.default_outbound_access_enabled])
    error_message = "All subnets must disable implicit default outbound access."
  }
  assert {
    condition     = azurerm_subnet.this["app"].private_endpoint_network_policies == "Disabled"
    error_message = "Private endpoint network policies must default to Disabled."
  }
  assert {
    condition     = alltrue([for key, name in output.names : key == name])
    error_message = "The input key must remain the exact Azure subnet name, including reserved names."
  }
  assert {
    condition     = length(azurerm_network_security_group.this) == 0 && length(azurerm_route_table.this) == 0
    error_message = "Optional NSGs and route tables must not be created implicitly."
  }
}

run "explicit_nsg_routes_and_delegation" {
  command = apply

  variables {
    tags = { environment = "test" }
    subnets = {
      app = {
        address_prefixes                  = ["10.20.1.0/24"]
        service_endpoints                 = ["Microsoft.Storage"]
        private_endpoint_network_policies = "Enabled"
        network_security_group = {
          name = "nsg-app"
          rules = {
            allow-https = {
              priority               = 100
              direction              = "Inbound"
              access                 = "Allow"
              protocol               = "Tcp"
              source_address_prefix  = "10.20.0.0/16"
              destination_port_range = "443"
            }
            deny-internet = {
              priority                   = 100
              direction                  = "Outbound"
              access                     = "Deny"
              protocol                   = "*"
              source_address_prefix      = "*"
              destination_address_prefix = "Internet"
              destination_port_range     = "*"
            }
          }
        }
        route_table = {
          name                          = "rt-app"
          bgp_route_propagation_enabled = false
          routes = {
            default = {
              address_prefix         = "0.0.0.0/0"
              next_hop_type          = "VirtualAppliance"
              next_hop_in_ip_address = "10.20.0.4"
            }
            monitor = {
              address_prefix = "AzureMonitor"
              next_hop_type  = "Internet"
            }
          }
        }
        delegation = {
          name         = "web"
          service_name = "Microsoft.Web/serverFarms"
          actions      = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_network_security_rule.this) == 2 && length(azurerm_route.this) == 2
    error_message = "All explicit NSG rules and routes must be managed as separate resources."
  }
  assert {
    condition     = azurerm_network_security_rule.this[jsonencode(["app", "allow-https"])].source_port_range == "*"
    error_message = "NSG source ports must default to wildcard."
  }
  assert {
    condition     = azurerm_route.this[jsonencode(["app", "default"])].next_hop_in_ip_address == "10.20.0.4" && !azurerm_route_table.this["app"].bgp_route_propagation_enabled
    error_message = "Explicit appliance next-hop and BGP settings must be preserved."
  }
  assert {
    condition     = azurerm_network_security_group.this["app"].tags["environment"] == "test" && azurerm_route_table.this["app"].tags["environment"] == "test"
    error_message = "Tags must reach both NSGs and route tables."
  }
  assert {
    condition     = one(azurerm_subnet.this["app"].delegation).name == "web" && contains(azurerm_subnet.this["app"].service_endpoints, "Microsoft.Storage")
    error_message = "Delegation and service endpoints must pass through to the subnet."
  }
  assert {
    condition     = output.ids["app"] == azurerm_subnet.this["app"].id && output.network_security_group_ids["app"] == azurerm_network_security_group.this["app"].id && output.route_table_ids["app"] == azurerm_route_table.this["app"].id
    error_message = "Output IDs must be keyed by subnet name."
  }
}

run "removing_all_custom_rules_and_routes" {
  command = plan
  variables {
    subnets = {
      app = {
        address_prefixes       = ["10.20.1.0/24"]
        network_security_group = { name = "nsg-app" }
        route_table            = { name = "rt-app" }
      }
    }
  }
  assert {
    condition     = length(azurerm_network_security_rule.this) == 0 && length(azurerm_route.this) == 0 && length(azurerm_network_security_group.this) == 1 && length(azurerm_route_table.this) == 1
    error_message = "Removing all custom rules and routes must remove their resources while retaining their containers."
  }
}

run "invalid_cidr" {
  command = plan
  variables {
    subnets = { app = { address_prefixes = ["10.20.300.0/24"] } }
  }
  expect_failures = [var.subnets]
}

run "empty_prefixes" {
  command = plan
  variables {
    subnets = { app = { address_prefixes = [] } }
  }
  expect_failures = [var.subnets]
}

run "invalid_private_endpoint_policy" {
  command = plan
  variables {
    subnets = { app = { address_prefixes = ["10.20.1.0/24"], private_endpoint_network_policies = "invalid" } }
  }
  expect_failures = [var.subnets]
}

run "reject_reserved_subnet_nsg" {
  command = plan
  variables {
    subnets = {
      GatewaySubnet = {
        address_prefixes       = ["10.20.1.0/27"]
        network_security_group = { name = "nsg-gateway" }
      }
    }
  }
  expect_failures = [var.subnets]
}

run "reject_duplicate_priority_in_same_direction" {
  command = plan
  variables {
    subnets = {
      app = {
        address_prefixes = ["10.20.1.0/24"]
        network_security_group = {
          name = "nsg-app"
          rules = {
            first  = { priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "VirtualNetwork", destination_port_range = "443" }
            second = { priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "VirtualNetwork", destination_port_range = "8443" }
          }
        }
      }
    }
  }
  expect_failures = [var.subnets]
}

run "reject_invalid_priority" {
  command = plan
  variables {
    subnets = {
      app = {
        address_prefixes = ["10.20.1.0/24"]
        network_security_group = {
          name  = "nsg-app"
          rules = { invalid = { priority = 99, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "VirtualNetwork", destination_port_range = "443" } }
        }
      }
    }
  }
  expect_failures = [var.subnets]
}

run "reject_invalid_port_range" {
  command = plan
  variables {
    subnets = {
      app = {
        address_prefixes = ["10.20.1.0/24"]
        network_security_group = {
          name  = "nsg-app"
          rules = { invalid = { priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "VirtualNetwork", destination_port_range = "70000" } }
        }
      }
    }
  }
  expect_failures = [var.subnets]
}

run "reject_appliance_without_ip" {
  command = plan
  variables {
    subnets = {
      app = {
        address_prefixes = ["10.20.1.0/24"]
        route_table = {
          name   = "rt-app"
          routes = { invalid = { address_prefix = "0.0.0.0/0", next_hop_type = "VirtualAppliance" } }
        }
      }
    }
  }
  expect_failures = [var.subnets]
}

run "reject_ip_for_non_appliance" {
  command = plan
  variables {
    subnets = {
      app = {
        address_prefixes = ["10.20.1.0/24"]
        route_table = {
          name   = "rt-app"
          routes = { invalid = { address_prefix = "0.0.0.0/0", next_hop_type = "Internet", next_hop_in_ip_address = "10.20.0.4" } }
        }
      }
    }
  }
  expect_failures = [var.subnets]
}
