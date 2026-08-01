# Terraform

Placeholder for the IaC version of this lab.

Planned layout:

```
terraform/
├── main.tf          # resource group, vnet, subnets
├── firewall.tf      # firewall, policy, DNAT rule collection
├── bastion.tf       # bastion host + public IP
├── vm.tf            # Ubuntu VM, NIC with no public IP, custom_data
├── variables.tf
├── outputs.tf       # firewall public IP, VM private IP
└── terraform.tfvars.example
```

Until this exists, use `../scripts/deploy.sh` for the Azure CLI equivalent.
