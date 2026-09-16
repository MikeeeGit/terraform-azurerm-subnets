# terraform-azurerm-subnets

[![Terraform CI](https://github.com/MikeeeGit/terraform-azurerm-subnets/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/MikeeeGit/terraform-azurerm-subnets/actions/workflows/ci.yml)

A Terraform module for subnets in an existing Azure virtual network, with optional network security groups, user-defined routes, service endpoints, and a service delegation. Subnets use exact names supplied by the caller, making reserved Azure service names work in every VNet.

This repository is the redesigned public successor to `AZ-TF-MOD-subnets`. Configuration is typed HCL; there are no implicit CSV files, root-directory lookups, embedded environment names, or provider credentials.

## Requirements

- Terraform `>= 1.9.0, < 2.0.0`.
- HashiCorp AzureRM provider `>= 4.0.0, < 5.0.0`, configured by the caller.
- An existing VNet in the supplied resource group. Its address space must contain the subnet prefixes.

Do not mix this module's standalone subnets with inline `subnet` blocks on the parent VNet. Do not manage its NSG rules or routes in another module or with inline blocks on the same NSG/route table.

## Usage

For a local checkout beside the calling Terraform root:

```hcl
module "subnets" {
  source = "../terraform-azurerm-subnets"

  resource_group_name  = "rg-network-example"
  location             = "uksouth"
  virtual_network_name = "vnet-example"
  tags                 = { environment = "example", managed_by = "terraform" }

  subnets = {
    app = {
      address_prefixes = ["10.20.1.0/24"]
      network_security_group = {
        name = "nsg-example-app"
        rules = {
          allow-https-from-vnet = {
            priority               = 100
            direction              = "Inbound"
            access                 = "Allow"
            protocol               = "Tcp"
            source_address_prefix  = "VirtualNetwork"
            destination_port_range = "443"
          }
        }
      }
    }
    AzureFirewallSubnet = {
      address_prefixes = ["10.20.2.0/26"]
    }
  }
}
```

Use a version tag or commit SHA when consuming a published Git source. See the [self-contained basic example](examples/basic) for provider configuration and prerequisite resources.

## Behavior and scope

Default outbound access is disabled for every subnet. Configure an explicit egress path, such as a NAT Gateway or firewall, when workloads need outbound internet access. This module does not create that path.

NSGs and route tables are opt-in. Creating an NSG with no custom rules leaves Azure's built-in default rules in effect, including virtual-network inbound access; neither an empty rules map nor the HTTPS example is a deny-all policy. NSG rules and routes are separate resources so removing the final entry removes the managed rule or route.

NSGs are rejected on `GatewaySubnet`, `AzureFirewallSubnet`, and `AzureFirewallManagementSubnet`. `AzureBastionSubnet` may have an NSG, but the caller must include the rules required by Azure Bastion. No name is prefixed, suffixed, or rewritten.

The default `private_endpoint_network_policies = "Disabled"` applies to private endpoints; it does not disable an associated NSG for ordinary workload interfaces. Choose `Enabled`, `NetworkSecurityGroupEnabled`, or `RouteTableEnabled` when private endpoints should participate in those policies.

Azure validates address-space containment, overlapping subnets, service-specific subnet sizing, service tags, delegations and actions, and region capabilities. This module validates CIDR syntax, names, policy enums, NSG rules and ports, and route next-hop consistency. It does not claim to validate every Azure service requirement offline.

NSG and route-table associations are created after the subnet. Subscriptions with Azure Policies requiring these associations in the initial subnet creation request need a different provisioning pattern. This module does not bypass those policies.

## Inputs

| Input | Type | Default | Meaning |
| --- | --- | --- | --- |
| `resource_group_name` | `string` | Required | Existing VNet's resource group; also used for NSGs and route tables. |
| `location` | `string` | Required | Region for NSGs and route tables; match the VNet. |
| `virtual_network_name` | `string` | Required | Existing VNet name. |
| `subnets` | `map(object)` | Required | Exact subnet names mapped to the definition below. `{}` creates nothing. |
| `tags` | `map(string)` | `{}` | Tags for NSGs and route tables. Azure subnets do not support tags. |

Each `subnets` value accepts:

| Field | Type | Default |
| --- | --- | --- |
| `address_prefixes` | `list(string)` | Required, nonempty valid CIDRs. |
| `service_endpoints` | `set(string)` | `[]` |
| `default_outbound_access_enabled` | `bool` | `false` |
| `private_endpoint_network_policies` | `string` | `"Disabled"` |
| `network_security_group` | `object` | `null` |
| `route_table` | `object` | `null` |
| `delegation` | `object` | `null` |

The complete type contract is in [variables.tf](variables.tf).

### Network security groups

`network_security_group` requires `name` and optionally accepts `rules` (a map, default `{}`). Each rule key is its exact Azure name. NSG names must be unique within this module. Each rule accepts:

| Field | Type | Default or allowed values |
| --- | --- | --- |
| `priority` | `number` | Required integer, 100-4096; unique within each direction of its NSG. |
| `direction` | `string` | Required: `Inbound` or `Outbound`. |
| `access` | `string` | Required: `Allow` or `Deny`. |
| `protocol` | `string` | Required: `*`, `Tcp`, `Udp`, `Icmp`, `Esp`, or `Ah`. |
| `source_port_range` | `string` | `"*"`; a port or inclusive range also accepted. |
| `destination_port_range` | `string` | Required: `"*"`, a port, or an inclusive range such as `"8000-8080"`. |
| `source_address_prefix` | `string` | Required: CIDR, address, service tag, or `"*"`. |
| `destination_address_prefix` | `string` | `"*"`; CIDR, address, or service tag also accepted. |
| `description` | `string` | `null`; maximum 140 characters when supplied. |

This initial API supports one source and destination prefix and one source and destination port range per rule. Use multiple named rules for additional ranges. Application security groups and existing externally managed NSGs are outside this module's scope.

### Route tables

`route_table` requires `name`, with optional `bgp_route_propagation_enabled` (default `true`) and `routes` (map, default `{}`). Each route key is its exact Azure name. Route-table names must be unique within this module. Each route requires `address_prefix` (CIDR or Azure service tag) and `next_hop_type` (`VirtualNetworkGateway`, `VnetLocal`, `Internet`, `VirtualAppliance`, or `None`).

Set `next_hop_in_ip_address` to an IPv4 address for `VirtualAppliance`; leave it unset for every other next-hop type. Example:

```hcl
route_table = {
  name = "rt-example-app"
  routes = {
    default-egress = {
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = "10.20.2.4"
    }
  }
}
```

This routes traffic to an existing reachable appliance; it does not create or configure that appliance.

### Delegation

`delegation` requires `name` and `service_name`. `actions` is an optional list, default `[]`. Supply the exact service-specific actions Azure expects to avoid drift from server-added defaults. One delegation is supported per subnet.

## Outputs

All outputs are maps keyed by the subnet input key.

| Output | Value |
| --- | --- |
| `ids` | Subnet resource IDs; dependency includes completed NSG and route-table associations. |
| `names` | Exact subnet names. |
| `address_prefixes` | Configured address-prefix lists. |
| `network_security_group_ids` | NSG IDs for subnets that requested one. |
| `route_table_ids` | Route-table IDs for subnets that requested one. |

## Migrating from AZ-TF-MOD-subnets

This is a new public API, not a drop-in update to an existing state file.

1. Convert the old subnet list to a map keyed by each **actual deployed subnet name**. Legacy generated prefixes are no longer added.
2. Rename `vnet_name` to `virtual_network_name`, wrap `address_prefix` as `address_prefixes`, and rename `endpoints` to `service_endpoints`.
3. Replace `security_group` flags and discovered CSV files with an explicit `network_security_group` object and typed rule map. Convert route CSV content to an explicit `route_table` and route map. Supply existing NSG and route-table names when retaining those resources.
4. Remove `label`, `location_abbreviated`, `environment`, and `vnet_suffix`; naming and tags belong to the caller.
5. Review outbound requirements before accepting the new `false` default. Provide explicit egress for workloads that need it.
6. Plan an explicit state migration/import for renamed resource addresses, association resources, and the split from inline rules/routes to standalone resources. Keep a secure state backup and inspect the plan for replacements. Do not run the old and new configurations against the same resources simultaneously.

No state migration is performed by this repository. Outputs exposing local paths and parsed CSV files have been removed. This module does not implement private DNS zone links or diagnostic settings; those belong to separate resources.

## Validation

```sh
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
terraform test
```

Tests use Terraform's mocked AzureRM provider. They cover reserved subnet names, private defaults, optional resources, custom rules/routes, tag and delegation propagation, removal of all custom rules/routes, and rejected inputs. The mock `apply` run creates only in-memory test state and makes no Azure API calls. Passing these tests is not proof of a deployment in Azure.

## References

- [AzureRM subnet resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet)
- [AzureRM network security rule resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule)
- [AzureRM route resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route)
- [Azure default security rules](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview#default-security-rules)
