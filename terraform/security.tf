resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # HTTP only from the firewall subnet. Nothing else on the internet has a
  # route here anyway, but defence in depth costs nothing.
  security_rule {
    name                       = "allow-http-from-firewall"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.firewall_subnet_prefix
    destination_address_prefix = "*"
  }

  # SSH only from the Bastion subnet. This is what replaces exposing port 22.
  security_rule {
    name                       = "allow-ssh-from-bastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# Forces all WebSubnet traffic bound for the internet through the firewall.
# Without this, return traffic for the DNAT rule takes an asymmetric path
# and the connection appears to hang rather than fail.
resource "azurerm_route_table" "web" {
  name                = "rt-web-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "web" {
  subnet_id      = azurerm_subnet.web.id
  route_table_id = azurerm_route_table.web.id
}
