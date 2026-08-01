#!/usr/bin/env bash
# Deletes everything. Firewall and Bastion bill hourly — run this when you're done.
set -euo pipefail
RG="rg-secure-web"
read -rp "Delete resource group '${RG}' and everything in it? [y/N] " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "Aborted."; exit 1; }
az group delete --name "$RG" --yes --no-wait
echo "Deletion started. Check with: az group show -n ${RG}"
