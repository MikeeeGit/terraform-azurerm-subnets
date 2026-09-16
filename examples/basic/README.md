# Basic CSV example

Creates a resource group, a VNet, two subnets, an enabled NSG with an internal HTTPS rule and a route table containing an AzureMonitor route. Names and addresses are synthetic.

The `app` subnet reads [its NSG CSV](config/uks/dev/dev_app_nsg.csv) and [route CSV](config/uks/dev/dev_app_route_table.csv) automatically from this root. The `private-endpoints` subnet has no NSG marker or CSV files. The example does not deploy a private endpoint; that is a logical subnet name.

`vnet_suffix = ""` produces `uks-dev-app` and `uks-dev-private-endpoints`. To retain the leaf module's original default suffix, omit that argument and review the changed names.

Credential-free checks:

```sh
terraform init -backend=false
terraform validate
```

The repository's root `terraform test` also runs this example with a mocked provider and verifies that its CSV files are found through `path.root`.

For an intentional deployment to your own disposable Azure subscription, configure Azure authentication and `ARM_SUBSCRIPTION_ID`, then review a normal Terraform plan before applying. This example contains no backend; state would be local unless you configure one.

Outbound access and private-endpoint policies are omitted, preserving provider behavior. No NAT gateway, firewall or other explicit egress resource is provisioned. The NSG retains Azure's built-in default rules, so the example HTTPS rule does not make the subnet HTTPS-only. No next-hop appliance is required by this example's AzureMonitor/Internet route.
