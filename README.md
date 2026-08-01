# azure-private-vm-bastion-firewall

**A private Azure VM with no public IP — reachable only through Azure Bastion and Azure Firewall.**

![Azure](https://img.shields.io/badge/Azure-0078D4?logo=microsoftazure&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu%2022.04-E95420?logo=ubuntu&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX-009639?logo=nginx&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

A hands-on lab that hosts a static site on an Ubuntu VM with **no public IP**. All inbound web traffic is forced through **Azure Firewall** (DNAT), and all administrative access goes through **Azure Bastion**. Anything else is dropped at the perimeter.

![Architecture diagram](/architecture.svg)

---

## Why this design

Giving a VM a public IP is the default path and the wrong one. It exposes SSH to the whole internet and leaves you defending port 22 with password policies and fail2ban. This lab removes that surface entirely:

| Concern | How it's handled |
|---|---|
| Inbound HTTP | Only via Azure Firewall public IP → DNAT to `10.0.3.4:80` |
| Administrative access | Azure Bastion over TLS 443 in the portal, Entra ID authenticated |
| SSH exposure | Port 22 is reachable only from `AzureBastionSubnet` |
| VM identity | No public IP, no direct route from the internet |
| Blast radius | Web tier isolated in its own subnet with its own NSG |

---

## Topology

| Resource | Name | Address space | Notes |
|---|---|---|---|
| Resource Group | `rg-secure-web` | — | Everything lives here, so cleanup is one delete |
| Virtual Network | `vnet-secure-web` | `10.0.0.0/16` | |
| Firewall subnet | `AzureFirewallSubnet` | `10.0.1.0/26` | Name is reserved — must match exactly |
| Bastion subnet | `AzureBastionSubnet` | `10.0.2.0/26` | Name is reserved — must match exactly, `/26` minimum |
| Web subnet | `WebSubnet` | `10.0.3.0/24` | Free-form name |
| Virtual machine | `vm-web-01` | `10.0.3.4` (private) | Ubuntu 22.04 LTS, NGINX |

> **Note:** `AzureFirewallSubnet` and `AzureBastionSubnet` are Azure-reserved names. A typo here is the single most common reason the deployment fails, and the error message is not obvious.

---

## Build order

![Deployment flow](/deployment-flow.svg)

### 1. Resource group

```bash
az group create --name rg-secure-web --location westeurope
```

### 2. Virtual network and subnets

```bash
az network vnet create \
  --resource-group rg-secure-web \
  --name vnet-secure-web \
  --address-prefix 10.0.0.0/16 \
  --subnet-name AzureFirewallSubnet \
  --subnet-prefix 10.0.1.0/26

az network vnet subnet create \
  --resource-group rg-secure-web --vnet-name vnet-secure-web \
  --name AzureBastionSubnet --address-prefix 10.0.2.0/26

az network vnet subnet create \
  --resource-group rg-secure-web --vnet-name vnet-secure-web \
  --name WebSubnet --address-prefix 10.0.3.0/24
```

### 3. Bastion and Firewall

Both need a Standard SKU public IP. In the portal you can enable them inline from the VNet blade; from the CLI, create the public IPs first, then the services.

```bash
az network public-ip create -g rg-secure-web -n pip-bastion  --sku Standard --allocation-method Static
az network public-ip create -g rg-secure-web -n pip-firewall --sku Standard --allocation-method Static

az network bastion create -g rg-secure-web -n bastion-secure-web \
  --public-ip-address pip-bastion --vnet-name vnet-secure-web --location westeurope

az network firewall create -g rg-secure-web -n fw-secure-web --location westeurope
```

Deployment takes roughly 10–15 minutes for each. Note the firewall's public IP when it finishes — you need it for step 6.

### 4. The VM — the critical setting

Deploy an Ubuntu 22.04 LTS VM into `WebSubnet`. On the **Networking** tab set **Public IP → None**. This is the whole point of the exercise; if the VM gets a public IP the firewall becomes decorative.

Use SSH key authentication, not a password.

### 5. NGINX

Either paste [`scripts/cloud-init.yaml`](scripts/cloud-init.yaml) into the **Custom data** field at VM creation time (preferred — it makes the repo repeatable), or connect through Bastion afterwards and run:

```bash
sudo apt update
sudo apt install -y nginx
sudo nano /var/www/html/index.html   # replace the default page
systemctl status nginx
```

To connect: open the VM in the portal → **Connect** → **Bastion** → enter your username and private key. No SSH client, no jump host of your own, no port 22 open to the internet.

### 6. DNAT rule

In the firewall policy, create a **DNAT rule collection**:

| Field | Value |
|---|---|
| Priority | 100 |
| Action | DNAT |
| Source | `*` (or your office CIDR — better) |
| Protocol | TCP |
| Destination | firewall public IP |
| Destination port | `4000` |
| Translated address | `10.0.3.4` |
| Translated port | `80` |

CLI equivalent:

```bash
az network firewall nat-rule create \
  -g rg-secure-web -f fw-secure-web \
  --collection-name dnat-web --priority 100 --action Dnat \
  -n allow-web --protocols TCP \
  --source-addresses '*' \
  --destination-addresses <FIREWALL_PUBLIC_IP> --destination-ports 4000 \
  --translated-address 10.0.3.4 --translated-port 80
```

You also need a **route table** on `WebSubnet` sending `0.0.0.0/0` to the firewall's private IP if you want return traffic and egress filtering to behave predictably.

---

## Verification

```
http://<FIREWALL_PUBLIC_IP>:4000
```

The NGINX page should load. Then confirm the negative case: there is no public IP on the VM to try, and port 80 on the firewall (rather than 4000) returns nothing, because no rule maps it.

---

## Cleanup

Azure Firewall and Bastion bill hourly regardless of traffic. This lab is not cheap to leave running.

```bash
az group delete --name rg-secure-web --yes --no-wait
```

---

## Roadmap

- [ ] Codify the whole build in Terraform (`/terraform`) so it stands up with `terraform apply`
- [ ] Add NSG rules explicitly rather than relying on defaults
- [ ] Add a UDR forcing all `WebSubnet` egress through the firewall
- [ ] Swap the DNAT port for an Application Gateway with WAF in front
- [ ] Add a network rule collection to allow only the package repositories the VM actually needs

---

## Repository layout

```
azure-private-vm-bastion-firewall/
├── README.md
├── docs/
│   ├── architecture.svg
│   └── deployment-flow.svg
└── scripts/
    └── cloud-init.yaml
```

---

## License

MIT
