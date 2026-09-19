# terraform-azurerm-subnets

Creates subnets in an existing Azure VNet, with CSV-driven Network Security Groups (NSGs), route tables and associations. This public edition preserves the original `AZ-TF-MOD-subnets` list interface, logical keys, naming conventions and policy-file workflow.

Terraform **>= 1.9, < 2.0** and AzureRM **>= 4.33, < 5.0** are required. CI uses Terraform 1.16.3. Configure the Azure provider and authentication in the calling root; this module contains no backend, subscription IDs or credentials.

## Usage

```hcl
module "subnets" {
  source = "git::https://github.com/MikeeeGit/terraform-azurerm-subnets.git?ref=v0.2.0"

  resource_group_name  = "example-uks-dev-network-rg"
  location             = "uksouth"
  vnet_name            = "example-uks-dev-vnet-01"
  label                = "uks-dev"
  location_abbreviated = "uks"
  environment          = "dev"
  vnet_suffix          = ""

  subnets = [{
    name           = "app"
    address_prefix = "10.20.1.0/24"
    security_group = "enabled"
    endpoints      = ["Microsoft.Storage"]
  }]

  tags = { environment = "dev" }
}
```

The VNet must already exist or be created by the caller. Passing a VNet resource's name creates the usual Terraform dependency. See the self-contained [basic example](examples/basic), including its CSV files.

## CSV policies

Place configuration under the **calling Terraform root**, rather than inside the downloaded module:

```text
config/
  uks/
    dev/
      dev_app_nsg.csv
      dev_app_route_table.csv
```

The general paths are `config/<location_abbreviated>/<environment>/<environment>_<logical-subnet-name>_nsg.csv` and `..._route_table.csv`. The filenames use the input `name`, even when the generated Azure subnet name has a prefix or suffix. Set `config_root` to override the configuration directory; the default is `${path.root}/config`. Files must exist before Terraform starts planning.

NSG CSV:

```csv
name,priority,direction,access,protocol,source_port_range,destination_port_range,source_address_prefix,destination_address_prefix
allow-https,100,Inbound,Allow,Tcp,*,443,VirtualNetwork,*
```

The nine original headers are required for nonempty files. An additional `description` column is supported. Standard quoted CSV fields work, including commas in descriptions. Other additional columns are ignored. Port values accept `*`, a port from 0 to 65535, or an ascending range such as `1024-65535`. Supply address prefixes or Azure service tags, and use `*` explicitly where intended. Rule names must be unique; priorities must be unique **within each direction**, between 100 and 4096. Supported protocols are `Tcp`, `Udp`, `Icmp`, `Esp`, `Ah` and `*`.

Route CSV:

```csv
name,address_prefix,next_hop_type,next_hop_in_ip_address
default,0.0.0.0/0,VirtualAppliance,10.20.0.4
monitor,AzureMonitor,Internet,
```

All four headers are required. Route names must be unique. Destinations accept a CIDR or service tag. Next-hop types are `VirtualNetworkGateway`, `VnetLocal`, `Internet`, `VirtualAppliance` and `None`. Only `VirtualAppliance` requires and accepts a next-hop IPv4 address. That appliance must be provisioned and configured separately; the synthetic address above is only a schema example.

| File state | NSG behavior when enabled | Route-table behavior |
|---|---|---|
| Missing | NSG with zero custom rules | No route table or association |
| Zero bytes / whitespace only | Same as missing | Same as missing |
| Valid headers only | Same as missing | Same as missing |
| Valid data rows | Manage all CSV rules inline | Create table, routes and association |
| Malformed CSV, missing headers or invalid rows | Plan fails with the file path | Plan fails with the file path |

Removing the final NSG row explicitly sets `security_rule = []`, clearing previously managed custom rules while retaining the NSG. Removing the final route row removes the table and its association, preserving original behavior. Deleting a policy file has the same effect as emptying it; review the plan for these changes.

NSG files are decoded and validated even when NSG creation is disabled, so their diagnostic outputs remain useful. An NSG keeps Azure's built-in default rules; an example HTTPS rule alone does **not** restrict all traffic to HTTPS. Do not manage the same NSG rules or route-table routes with separate Terraform resources or another deployment system.

## Inputs and naming

| Input | Type | Default / meaning |
|---|---|---|
| `resource_group_name` | `string` | Required; existing VNet's resource group |
| `location` | `string` | Required; Azure region for NSGs/tables |
| `vnet_name` | `string` | Required; existing VNet name |
| `label` | `string` | Required; ordinary subnet prefix; may be empty |
| `location_abbreviated` | `string` | Required; naming/config region selector |
| `environment` | `string` | Required; naming/config environment selector |
| `subnets` | `list(object)` | Required; schema below; may be empty |
| `vnet_suffix` | `string` | `"vnet01"`; set `""` to omit |
| `config_root` | `string` | `null` → calling root's `config/` |
| `tags` | `map(string)` | `{}`; applied to NSGs/tables only |

Each subnet requires `name`, `address_prefix`, `security_group` and `endpoints`. Logical names must be unique, and `address_prefix` is one CIDR string.

**`security_group` is an enable marker, not an NSG name.** Any nonempty string enables creation; `""` disables it. The string `"false"` still enables an NSG, matching the original interface. Use `endpoints = []` when no service endpoints are required.

| Resource | Generated Azure name |
|---|---|
| Ordinary subnet | `<label>-<vnet_suffix>-<logical-name>` |
| NSG | `<region>-<environment>-<vnet_suffix>-<logical-name>-nsg` |
| Route table | `<region>-<environment>-<vnet_suffix>-<logical-name>-rt` |
| Gateway route table | `GatewaySubnet-<region>-rt` |

Empty components are omitted. For example, `label = "uks-dev"`, `vnet_suffix = ""` and `name = "app"` produce `uks-dev-app`, `uks-dev-app-nsg` and `uks-dev-app-rt`.

`GatewaySubnet`, `AzureFirewallSubnet`, `AzureFirewallManagementSubnet` and `AzureBastionSubnet` keep their exact Azure names in every VNet. The former estate-specific hub allowlist is removed. NSGs are rejected for the gateway and both firewall subnet names. Bastion may have an NSG, but the caller must provide Azure's required Bastion rules.

Optional per-subnet attributes:

| Attribute | Type | Default |
|---|---|---|
| `default_outbound_access_enabled` | `bool` | `null` — provider behavior |
| `private_endpoint_network_policies` | `string` | `null` — provider behavior |
| `private_link_service_network_policies_enabled` | `bool` | `null` — provider behavior |
| `service_endpoint_policy_ids` | `list(string)` | `[]` |
| `bgp_route_propagation_enabled` | `bool` | `true` on a created route table |
| `delegation` | Object below | `null` |

```hcl
delegation = {
  name         = "web"
  service_name = "Microsoft.Web/serverFarms"
  actions      = ["Microsoft.Network/virtualNetworks/subnets/action"] # optional; defaults to []
}
```

Private endpoint policy values are `Disabled`, `Enabled`, `NetworkSecurityGroupEnabled` or `RouteTableEnabled`. Omitted outbound access settings are deliberately **not** forced to false: the original module left that decision to the provider. Set the value explicitly when choosing an egress policy, and configure any required NAT, firewall or other egress separately. Provider and Azure defaults can evolve; review provider upgrades.

## Outputs

Every map is keyed by the input **logical subnet name**.

| Output | Value |
|---|---|
| `subnets` | Original full subnet resource map |
| `file_paths` / `route_table_file_paths` | Original resolved CSV paths, including missing files |
| `subnet_nsg_rules` / `subnet_route_table_rules` | Original decoded CSV row lists |
| `rootpath` | Original calling-root diagnostic path |
| `subnet_ids` / `ids` | Subnet IDs after associations |
| `subnet_address_prefixes` / `address_prefixes` | Address-prefix lists |
| `names` | Generated Azure subnet names |
| `network_security_group_ids` / `route_table_ids` | Created policy-resource IDs |

This leaf module does not create VNets, peerings, DNS zones, private endpoints or diagnostic settings. The VNet and composition repositories own those capabilities.

## Examples

- [Basic](examples/basic): one VNet with CSV-backed subnet policy.
- [Hub and two spokes](examples/hub-spoke): CSV-backed policies, reciprocal peerings, caller-owned DNS and optional NAT egress.

## Validation and contribution

```sh
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
terraform -chdir=examples/basic init -backend=false
terraform -chdir=examples/basic validate
```

All tests use mocked AzureRM providers and synthetic CSV fixtures. They cover the calling-root path convention, populated/missing/header-only/zero-byte files, clearing the final NSG rule, routes and associations, naming, optional settings and rejected inputs. Tests require no Azure credentials and create no cloud resources. They do not prove Azure API behavior, actual network reachability, VNet CIDR containment or overlapping-prefix acceptance.

GitHub and Azure DevOps use the same pinned, credential-free validation templates. See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [migration notes](docs/MIGRATION.md) and [CHANGELOG.md](CHANGELOG.md). Apache-2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Provider references: [subnets](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet), [NSGs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group), [route tables](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table).

## CI change scope

Markdown-only edits use lightweight required GitHub checks and are excluded from automatic Azure validation builds. Changes to Terraform, application code, scripts, workflow definitions or executable examples still run full validation, including examples stored under docs/. Mixed changes also run full validation. Manual GitHub runs and unknown Git comparison ranges default to full validation.
