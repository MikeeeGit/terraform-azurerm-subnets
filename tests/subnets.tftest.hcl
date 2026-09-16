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
  vnet_name            = "vnet-test"
  label                = "uks-dev"
  location_abbreviated = "uks"
  environment          = "dev"
  config_root          = "tests/fixtures/not-present"
  subnets = [{
    name           = "app"
    address_prefix = "10.20.1.0/24"
    security_group = "enable"
    endpoints      = []
  }]
}

run "missing_csv_preserves_original_defaults" {
  command = plan
  assert {
    condition     = azurerm_subnet.subnets["app"].name == "uks-dev-vnet01-app" && azurerm_network_security_group.nsgs["app"].name == "uks-dev-vnet01-app-nsg"
    error_message = "Names must preserve the original label/suffix convention and treat security_group only as an enable flag."
  }
  assert {
    condition     = length(azurerm_network_security_group.nsgs["app"].security_rule) == 0 && length(azurerm_route_table.route_tables) == 0
    error_message = "Missing CSVs must leave an enabled NSG with explicitly empty custom rules, and create no route table."
  }
  assert {
    condition     = length(output.subnet_nsg_rules["app"]) == 0 && length(output.subnet_route_table_rules["app"]) == 0
    error_message = "Diagnostic outputs must distinguish the logical subnet even when both policy files are absent."
  }
  assert {
    condition     = azurerm_subnet.subnets["app"].default_outbound_access_enabled == null && azurerm_subnet.subnets["app"].private_endpoint_network_policies == null
    error_message = "Omitted optional settings must be passed as null so the provider, rather than the module, chooses its defaults."
  }
}

run "default_config_path_is_calling_root" {
  command = plan
  variables { config_root = null }
  assert {
    condition     = output.file_paths["app"] == "${output.rootpath}/config/uks/dev/dev_app_nsg.csv" && output.route_table_file_paths["app"] == "${output.rootpath}/config/uks/dev/dev_app_route_table.csv"
    error_message = "Default discovery must use the calling root's config/<region>/<environment> layout and logical subnet name."
  }
}

run "populated_csv_applies_rules_routes_and_settings" {
  command = apply
  variables {
    config_root = "tests/fixtures/populated"
    vnet_suffix = ""
    tags        = { environment = "test" }
    subnets = [{
      name                                          = "app"
      address_prefix                                = "10.20.1.0/24"
      security_group                                = "legacy-marker-is-not-the-name"
      endpoints                                     = ["Microsoft.Storage"]
      default_outbound_access_enabled               = false
      private_endpoint_network_policies             = "Enabled"
      private_link_service_network_policies_enabled = false
      bgp_route_propagation_enabled                 = false
      delegation = {
        name         = "web"
        service_name = "Microsoft.Web/serverFarms"
        actions      = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }]
  }
  assert {
    condition     = azurerm_subnet.subnets["app"].name == "uks-dev-app" && azurerm_network_security_group.nsgs["app"].name == "uks-dev-app-nsg" && azurerm_route_table.route_tables["app"].name == "uks-dev-app-rt"
    error_message = "An empty suffix must preserve root-stack names."
  }
  assert {
    condition     = length(azurerm_network_security_group.nsgs["app"].security_rule) == 2 && length(azurerm_route_table.route_tables["app"].route) == 2
    error_message = "Both CSV files must be applied in full, including equal priorities in different directions."
  }
  assert {
    condition     = one([for rule in azurerm_network_security_group.nsgs["app"].security_rule : rule if rule.name == "allow-https"]).description == "HTTPS, internal only"
    error_message = "Quoted CSV fields and the optional description column must be preserved."
  }
  assert {
    condition     = one([for route in azurerm_route_table.route_tables["app"].route : route if route.name == "default"]).next_hop_in_ip_address == "10.20.0.4" && !azurerm_route_table.route_tables["app"].bgp_route_propagation_enabled
    error_message = "Routes must preserve appliance hops and the optional BGP setting."
  }
  assert {
    condition     = !azurerm_subnet.subnets["app"].default_outbound_access_enabled && azurerm_subnet.subnets["app"].private_endpoint_network_policies == "Enabled" && !azurerm_subnet.subnets["app"].private_link_service_network_policies_enabled
    error_message = "Explicit subnet policy choices must reach the provider."
  }
  assert {
    condition     = one(azurerm_subnet.subnets["app"].delegation).name == "web" && contains(azurerm_subnet.subnets["app"].service_endpoints, "Microsoft.Storage")
    error_message = "Delegation and service endpoints must be retained."
  }
  assert {
    condition     = azurerm_network_security_group.nsgs["app"].tags["environment"] == "test" && azurerm_route_table.route_tables["app"].tags["environment"] == "test"
    error_message = "Both taggable resource types must receive explicit tags."
  }
  assert {
    condition     = output.subnets["app"].id == output.subnet_ids["app"] && output.ids["app"] == azurerm_subnet_network_security_group_association.nsgs["app"].subnet_id && output.route_table_ids["app"] == azurerm_subnet_route_table_association.route_tables["app"].route_table_id
    error_message = "Original resource outputs, convenience IDs and associations must share logical keys."
  }
}

run "removing_final_custom_rules_is_explicit" {
  command = plan
  variables {
    config_root = "tests/fixtures/header-only"
    vnet_suffix = ""
  }
  assert {
    condition     = length(azurerm_network_security_group.nsgs["app"].security_rule) == 0 && length(azurerm_network_security_group.nsgs) == 1
    error_message = "After a populated mock apply, clearing the CSV must explicitly plan zero custom NSG rules while retaining the NSG."
  }
  assert {
    condition     = length(azurerm_route_table.route_tables) == 0 && length(azurerm_subnet_route_table_association.route_tables) == 0
    error_message = "Removing the final route must remove the route table and its association, matching original ownership."
  }
}

run "zero_byte_files_are_empty" {
  command = plan
  variables { config_root = "tests/fixtures/empty" }
  assert {
    condition     = length(output.subnet_nsg_rules["app"]) == 0 && length(output.subnet_route_table_rules["app"]) == 0 && length(azurerm_network_security_group.nsgs["app"].security_rule) == 0
    error_message = "Zero-byte files are intentional empty policies."
  }
}

run "disabled_nsg_does_not_discard_csv_outputs" {
  command = plan
  variables {
    config_root = "tests/fixtures/populated"
    subnets = [{
      name           = "app"
      address_prefix = "10.20.1.0/24"
      security_group = ""
      endpoints      = []
    }]
  }
  assert {
    condition     = length(azurerm_network_security_group.nsgs) == 0 && length(output.subnet_nsg_rules["app"]) == 2 && length(azurerm_route_table.route_tables) == 1
    error_message = "The marker disables only NSG creation; decoded policy and independent routes remain available."
  }
}

run "reserved_names_and_gateway_route_name" {
  command = plan
  variables {
    config_root = "tests/fixtures/populated"
    vnet_name   = "example-custom-hub"
    subnets = [
      { name = "GatewaySubnet", address_prefix = "10.20.1.0/27", security_group = "", endpoints = [] },
      { name = "AzureFirewallSubnet", address_prefix = "10.20.2.0/26", security_group = "", endpoints = [] },
      { name = "AzureFirewallManagementSubnet", address_prefix = "10.20.3.0/26", security_group = "", endpoints = [] },
      { name = "AzureBastionSubnet", address_prefix = "10.20.4.0/26", security_group = "enabled", endpoints = [] }
    ]
  }
  assert {
    condition     = alltrue([for name, subnet in azurerm_subnet.subnets : name == subnet.name]) && azurerm_route_table.route_tables["GatewaySubnet"].name == "GatewaySubnet-uks-rt"
    error_message = "Reserved Azure names and the original gateway route name must work without a hardcoded hub VNet allowlist."
  }
  assert {
    condition     = keys(azurerm_network_security_group.nsgs) == ["AzureBastionSubnet"]
    error_message = "Only the explicitly enabled supported NSG should be created."
  }
}

run "reject_invalid_cidr" {
  command = plan
  variables {
    subnets = [{ name = "app", address_prefix = "10.300.0.0/24", security_group = "", endpoints = [] }]
  }
  expect_failures = [var.subnets]
}

run "reject_duplicate_subnet_names" {
  command = plan
  variables {
    subnets = [
      { name = "app", address_prefix = "10.20.1.0/24", security_group = "", endpoints = [] },
      { name = "app", address_prefix = "10.20.2.0/24", security_group = "", endpoints = [] }
    ]
  }
  expect_failures = [var.subnets]
}

run "reject_forbidden_nsg" {
  command = plan
  variables {
    subnets = [{ name = "GatewaySubnet", address_prefix = "10.20.1.0/27", security_group = "enabled", endpoints = [] }]
  }
  expect_failures = [var.subnets]
}

run "reject_invalid_endpoint_policy" {
  command = plan
  variables {
    subnets = [{ name = "app", address_prefix = "10.20.1.0/24", security_group = "", endpoints = [], private_endpoint_network_policies = "invalid" }]
  }
  expect_failures = [var.subnets]
}

run "reject_invalid_header" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-header" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_header_only" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-header-only" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_malformed" {
  command = plan
  variables { config_root = "tests/fixtures/malformed" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_priority" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-priority" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_duplicate_priority" {
  command = plan
  variables { config_root = "tests/fixtures/duplicate-priority" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_duplicate_name" {
  command = plan
  variables { config_root = "tests/fixtures/duplicate-name" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_port" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-port" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_port_range" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-port-range" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_enum" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-enum" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_route" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-route" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_hop_ip" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-hop-ip" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_invalid_route_prefix" {
  command = plan
  variables { config_root = "tests/fixtures/invalid-route-prefix" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}

run "reject_duplicate_route" {
  command = plan
  variables { config_root = "tests/fixtures/duplicate-route" }
  expect_failures = [azurerm_subnet.subnets["app"]]
}
