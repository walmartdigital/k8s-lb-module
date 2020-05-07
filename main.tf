terraform {
  required_version = ">= 0.12"
}

data "azurerm_resource_group" "main" {
  name = var.resource_group
}

resource "azurerm_public_ip" "public_ip" {
  count               = length(var.public_ips)
  name                = "${var.cluster_name}-${var.environment}-${values(var.public_ips)[count.index].target}-${var.name_suffix}-${values(var.public_ips)[count.index].name}-pip"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.sku
  allocation_method   = "Static"

  tags = merge(var.default_tags, map("cluster", "${var.cluster_name}-${var.environment}-${var.name_suffix}"))
}

resource "azurerm_lb" "load_balancer" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-lb"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.sku

  dynamic "frontend_ip_configuration" {
    iterator = pub
    for_each = data.azurerm_public_ip.pip  
    content {
      name                          = "${pub.name}-frontend"
      public_ip_address_id          = join("", azurerm_public_ip.public_ip.*.id)
    }

  }

  dynamic "frontend_ip_configuration" {
    iterator = priv
    for_each = var.private_ips  
    content {
      name                          = "${var.cluster_name}-${var.environment}-${priv.target}-${var.name_suffix}-${priv.name}-pip-frontend"
      private_ip_address_allocation = var.frontend_private_ip_address_allocation
      private_ip_address            = priv.address_allocation == "Static" ? priv.ip_address : ""
    }

  }

  tags = merge(var.default_tags, map("cluster", "${var.cluster_name}-${var.environment}-${var.name_suffix}"))
}

resource "azurerm_lb_backend_address_pool" "address_pool" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-addresspool"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer.id
}

resource "azurerm_lb_rule" "lb_rule" {
  count                          = length(var.lb_ports)
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer.id
  name                           = element(keys(var.lb_ports), count.index)
  protocol                       = values(var.lb_ports)[count.index][1]
  frontend_port                  = values(var.lb_ports)[count.index][0]
  backend_port                   = values(var.lb_ports)[count.index][2]
  frontend_ip_configuration_name = "${var.cluster_name}-${var.environment}-${values(var.lb_ports)[count.index][5]}-${var.name_suffix}-${values(var.lb_ports)[count.index][6]}-pip-frontend"
  enable_floating_ip             = false
  backend_address_pool_id        = azurerm_lb_backend_address_pool.address_pool.id
  idle_timeout_in_minutes        = 5
  probe_id                       = element(concat(azurerm_lb_probe.lb_probe.*.id, list("")), count.index)
  depends_on                     = [azurerm_lb_probe.lb_probe]
}

resource "azurerm_lb_probe" "lb_probe" {
  count               = length(var.lb_ports)
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer.id
  name                = element(keys(var.lb_ports), count.index)
  protocol            = values(var.lb_ports)[count.index][4] != "" ? "http" : "Tcp"
  port                = values(var.lb_ports)[count.index][3]
  interval_in_seconds = var.lb_probe_interval
  number_of_probes    = var.lb_probe_unhealthy_threshold
  request_path        = values(var.lb_ports)[count.index][4] != "" ? values(var.lb_ports)[count.index][4] : ""
}
