locals {
  rootpath         = path.root
  file_path_config = var.config_root == null ? "${local.rootpath}/config" : trimsuffix(var.config_root, "/")
  subnets_by_name  = { for name, entries in { for subnet in var.subnets : subnet.name => subnet... } : name => entries[0] }

  file_paths = {
    for name, subnet in local.subnets_by_name :
    name => "${local.file_path_config}/${var.location_abbreviated}/${var.environment}/${var.environment}_${name}_nsg.csv"
  }
  route_table_file_paths = {
    for name, subnet in local.subnets_by_name :
    name => "${local.file_path_config}/${var.location_abbreviated}/${var.environment}/${var.environment}_${name}_route_table.csv"
  }

  # Missing files and deliberately empty files both mean no custom policy rows.
  nsg_csv = {
    for name, filename in local.file_paths : name => fileexists(filename) ? trimspace(file(filename)) : ""
  }
  route_csv = {
    for name, filename in local.route_table_file_paths : name => fileexists(filename) ? trimspace(file(filename)) : ""
  }
  subnet_nsg_rules = {
    for name, contents in local.nsg_csv : name => contents == "" ? [] : try(csvdecode(contents), [])
  }
  subnet_route_table_rules = {
    for name, contents in local.route_csv : name => contents == "" ? [] : try(csvdecode(contents), [])
  }
  nsg_required_headers = [
    "name", "priority", "direction", "access", "protocol", "source_port_range",
    "destination_port_range", "source_address_prefix", "destination_address_prefix"
  ]
  route_required_headers = ["name", "address_prefix", "next_hop_type", "next_hop_in_ip_address"]

  # A synthetic data row lets header-only files receive the same schema checks.
  # Policy column names cannot contain commas; quoted ordinary headers work.
  nsg_headers = {
    for name, contents in local.nsg_csv : name => contents == "" ? [] : try(keys(csvdecode(
      "${split("\n", contents)[0]}\n${join(",", [for column in split(",", split("\n", contents)[0]) : "schema"])}"
    )[0]), [])
  }
  route_headers = {
    for name, contents in local.route_csv : name => contents == "" ? [] : try(keys(csvdecode(
      "${split("\n", contents)[0]}\n${join(",", [for column in split(",", split("\n", contents)[0]) : "schema"])}"
    )[0]), [])
  }
  nsg_csv_valid = {
    for name, contents in local.nsg_csv : name => contents == "" ? true :
    can(csvdecode(contents)) && length(setsubtract(local.nsg_required_headers, local.nsg_headers[name])) == 0
  }
  route_csv_valid = {
    for name, contents in local.route_csv : name => contents == "" ? true :
    can(csvdecode(contents)) && length(setsubtract(local.route_required_headers, local.route_headers[name])) == 0
  }

  nsg_rules_valid = {
    for name, rules in local.subnet_nsg_rules : name =>
    alltrue([for rule in rules : try(
      length(trimspace(rule.name)) > 0 &&
      tonumber(rule.priority) >= 100 && tonumber(rule.priority) <= 4096 && floor(tonumber(rule.priority)) == tonumber(rule.priority) &&
      contains(["Inbound", "Outbound"], rule.direction) &&
      contains(["Allow", "Deny"], rule.access) &&
      contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], rule.protocol) &&
      length(trimspace(rule.source_address_prefix)) > 0 &&
      length(trimspace(rule.destination_address_prefix)) > 0 &&
      alltrue([for port in [rule.source_port_range, rule.destination_port_range] :
        port == "*" ? true : (
          can(regex("^[0-9]+(-[0-9]+)?$", port)) &&
          alltrue([for part in split("-", port) : tonumber(part) >= 0 && tonumber(part) <= 65535]) &&
          (length(split("-", port)) == 2 ? tonumber(split("-", port)[0]) <= tonumber(split("-", port)[1]) : true)
        )
      ]), false
    )]) &&
    length(distinct([for rule in rules : try(lower(rule.name), "")])) == length(rules) &&
    length(distinct([for rule in rules : try("${rule.direction}:${tonumber(rule.priority)}", "")])) == length(rules)
  }
  route_rules_valid = {
    for name, rules in local.subnet_route_table_rules : name =>
    alltrue([for rule in rules : try(
      length(trimspace(rule.name)) > 0 &&
      (can(cidrhost(rule.address_prefix, 0)) || can(regex("^[A-Za-z][A-Za-z0-9.-]*$", rule.address_prefix))) &&
      contains(["VirtualNetworkGateway", "VnetLocal", "Internet", "VirtualAppliance", "None"], rule.next_hop_type) &&
      (rule.next_hop_type == "VirtualAppliance" ?
        can(cidrhost("${rule.next_hop_in_ip_address}/32", 0)) &&
        can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", rule.next_hop_in_ip_address)) :
      trimspace(rule.next_hop_in_ip_address) == ""), false
    )]) && length(distinct([for rule in rules : try(lower(rule.name), "")])) == length(rules)
  }

  # Azure's reserved names apply to every VNet, without an estate-specific allowlist.
  special_subnet_names = ["AzureFirewallSubnet", "AzureFirewallManagementSubnet", "GatewaySubnet", "AzureBastionSubnet"]
  subnet_names = {
    for name, subnet in local.subnets_by_name : name =>
    contains(local.special_subnet_names, name) ? name : join("-", compact([var.label, var.vnet_suffix, name]))
  }
  nsg_names = {
    for name, subnet in local.subnets_by_name :
    name => join("-", compact([var.location_abbreviated, var.environment, var.vnet_suffix, name, "nsg"]))
  }
  route_table_names = {
    for name, subnet in local.subnets_by_name : name =>
    name == "GatewaySubnet" ? "GatewaySubnet-${var.location_abbreviated}-rt" : join("-", compact([var.location_abbreviated, var.environment, var.vnet_suffix, name, "rt"]))
  }
}
