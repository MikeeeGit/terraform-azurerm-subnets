# Changelog

## 0.3.0

- Add a hub and two-spoke composition example with CSV subnet policy, reciprocal peering and optional NAT.
- Add four mocked topology/policy checks and validate the example on both CI platforms.
- Preserve the existing module interface.

## 0.2.0

Restore the original subnet module's list interface, logical keys, resource addresses, naming and first-class root-relative CSV workflow. Retain full-resource and diagnostic outputs, with additive ID/name/prefix outputs.

- Preserve NSG creation through the original nonempty `security_group` marker and route-table creation only for populated route CSVs.
- Fix removal of the final custom NSG rule with an explicit empty rule collection.
- Validate CSV schemas and policy rows; support missing, zero-byte and header-only files consistently.
- Preserve reserved Azure subnet names without fixed estate-specific VNet names, and reject unsupported gateway/firewall NSG associations.
- Add explicit tags and optional subnet/delegation/BGP settings. Omitted outbound access uses provider behavior.
- Replace provisional examples with synthetic CSV examples and expand credential-free mocked tests.
- Require Terraform >= 1.9, < 2.0 and AzureRM >= 4.33, < 5.0.

This is a breaking change from provisional 0.1.0; see [migration notes](docs/MIGRATION.md).

## 0.1.0

Initial provisional public foundation. Introduced a typed map interface and separate rule resources, synthetic examples, credential-free validation and tests, dependency pins and explicit migration boundaries. Superseded by 0.2.0's restored original CSV operating model.
