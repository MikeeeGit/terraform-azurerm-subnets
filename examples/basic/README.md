# Basic example

Creates a resource group, a VNet, two subnets, and an NSG with an explicit HTTPS rule. Use a disposable subscription and review the plan before applying.

```sh
export ARM_SUBSCRIPTION_ID="<your-subscription-id>"
az login
terraform init
terraform plan
```

Both subnets disable default outbound internet access. Workloads that need outbound connectivity require a separately configured NAT Gateway, firewall, or other explicit egress path. This example provisions none.

The NSG retains Azure's built-in default rules, including virtual-network inbound access. The HTTPS rule demonstrates the API; it does not make the subnet HTTPS-only.

The resource group and VNet exist only to make this example self-contained. The module itself accepts an existing VNet.
