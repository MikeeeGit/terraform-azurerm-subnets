# Migration and ownership boundaries

## From the original AZ-TF-MOD-subnets interface

Version 0.2.0 restores the original list-based subnet input, naming components, root-relative CSV discovery and logical subnet keys. Preserve the caller's module block label, each logical subnet name, all naming inputs and the CSV paths when comparing configurations.

The original Terraform resource addresses are retained:

```text
azurerm_subnet.subnets["<logical-name>"]
azurerm_network_security_group.nsgs["<logical-name>"]
azurerm_subnet_network_security_group_association.nsgs["<logical-name>"]
azurerm_route_table.route_tables["<logical-name>"]
azurerm_subnet_route_table_association.route_tables["<logical-name>"]
```

The original outputs `subnets`, `file_paths`, `rootpath`, `subnet_nsg_rules`, `route_table_file_paths` and `subnet_route_table_rules` are retained. Convenience ID/prefix outputs are additive.

The default subnet suffix remains `vnet01`. A root stack that previously passed `vnet_suffix = ""` must keep doing so. `security_group` remains a nonempty-string enable marker; it never named or looked up an existing NSG.

Deliberate corrections and additions:

- Reserved service subnet names remain exact in every VNet, removing the old fixed hub-name allowlist. Gateway route tables retain `GatewaySubnet-<region>-rt`. If an earlier caller produced prefixed reserved names outside that allowlist, review replacement explicitly.
- Gateway and firewall subnet NSG requests fail validation rather than reaching an unsupported Azure configuration.
- An enabled NSG receives an explicit empty custom-rule collection when its CSV becomes empty or missing. This fixes the original dynamic-block omission that could leave the final old custom rule unmanaged.
- A zero-byte CSV is accepted as an intentional empty policy. Malformed CSV, incomplete headers and invalid rows now fail with the path identified.
- Route-table creation still depends on there being at least one route row. Removing the last row removes the table and association.
- Tags and optional delegation, endpoint policies, outbound access and BGP controls are additive. Omitted subnet policy settings remain null rather than imposing a new outbound policy.
- AzureRM now requires 4.33 or newer within major version 4, consistently with the companion modules; Terraform requires 1.9 or newer within major version 1.

The public examples target synthetic infrastructure and **new state**. They are not a migration of the original estate. Do not copy original state, tfvars, backend files, identities or private configuration into the public repositories. Changing a repository name in a surrounding delivery framework can change the derived state key; never point that at an existing estate by accident.

For a separately approved adoption of existing infrastructure, inspect a saved plan against a protected copy of its existing state, confirm every generated name/resource address and handle any import or state move deliberately. This repository performs no automatic state migration.

## From the provisional 0.1.0 public module

This is a breaking 0.x interface change. The provisional version accepted a map keyed by the exact Azure subnet name, inline typed rule/route maps and `virtual_network_name`. It used `.this` resource addresses and separate NSG-rule/route resources. That redesign omitted the original CSV operating model.

For new installations:

1. Use `vnet_name` and a `subnets` list with `name`, `address_prefix`, `security_group` and `endpoints`.
2. Choose `label`, `location_abbreviated`, `environment` and `vnet_suffix` explicitly.
3. Move policy definitions to the CSV schemas documented in the README.
4. Preserve any explicit outbound-access choice. Version 0.1.0 forced false by default; version 0.2.0 leaves omitted values to the provider.
5. Review the generated Azure names and outputs before deployment.

If 0.1.0 was already deployed, do not simply switch versions or apply a generic moved block. Resource keys and names can differ, and moving between separately managed rules and inline rules requires an ownership transition. Do not let both configurations manage the same NSG or route table. Plan a resource-by-resource migration or deploy a separate environment with fresh state. No generic state-move recipe is claimed safe for all callers.
