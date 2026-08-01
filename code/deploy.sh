#!/usr/bin/env bash
# Provisions the full lab with Azure CLI.
# Usage: ./scripts/deploy.sh
# Requires: az CLI, logged in via `az login`.

set -euo pipefail

RG="rg-secure-web"
LOCATION="westeurope"
VNET="vnet-secure-web"
VM="vm-web-01"
ADMIN_USER="azureuser"

echo "==> Resource group"
az group create --name "$RG" --location "$LOCATION" --output none

echo "==> VNet and subnets"
az network vnet create \
  --resource-group "$RG" --name "$VNET" \
  --address-prefix 10.0.0.0/16 \
  --subnet-name AzureFirewallSubnet --subnet-prefix 10.0.1.0/26 --output none

az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" \
  --name AzureBastionSubnet --address-prefix 10.0.2.0/26 --output none

az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" \
  --name WebSubnet --address-prefix 10.0.3.0/24 --output none

echo "==> Public IPs"
az network public-ip create -g "$RG" -n pip-bastion  --sku Standard --allocation-method Static --output none
az network public-ip create -g "$RG" -n pip-firewall --sku Standard --allocation-method Static --output none

echo "==> Bastion (this takes ~10 minutes)"
az network bastion create -g "$RG" -n bastion-secure-web \
  --public-ip-address pip-bastion --vnet-name "$VNET" --location "$LOCATION" --output none

echo "==> Firewall"
az network firewall create -g "$RG" -n fw-secure-web --location "$LOCATION" --output none

echo "==> VM — no public IP, NGINX via cloud-init"
az vm create \
  --resource-group "$RG" --name "$VM" \
  --image Ubuntu2204 --size Standard_B1s \
  --vnet-name "$VNET" --subnet WebSubnet \
  --public-ip-address "" \
  --admin-username "$ADMIN_USER" --generate-ssh-keys \
  --custom-data ./scripts/cloud-init.yaml --output none

VM_IP=$(az vm show -g "$RG" -n "$VM" -d --query privateIps -o tsv)
FW_IP=$(az network public-ip show -g "$RG" -n pip-firewall --query ipAddress -o tsv)

echo "==> DNAT rule 4000 -> ${VM_IP}:80"
az network firewall nat-rule create \
  -g "$RG" -f fw-secure-web \
  --collection-name dnat-web --priority 100 --action Dnat \
  -n allow-web --protocols TCP \
  --source-addresses '*' \
  --destination-addresses "$FW_IP" --destination-ports 4000 \
  --translated-address "$VM_IP" --translated-port 80 --output none

echo
echo "Done. Browse to: http://${FW_IP}:4000"
echo "Tear down with: ./scripts/destroy.sh"
