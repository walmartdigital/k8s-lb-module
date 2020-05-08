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

resource "azurerm_lb" "load_balancer_public" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-lb"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.sku

  dynamic "frontend_ip_configuration" {
    iterator = pub
    for_each = var.public_ips
    content {
      name                          = "${var.cluster_name}-${var.environment}-${pub.value.target}-${var.name_suffix}-${pub.value.name}-frontend"
      public_ip_address_id          = azurerm_public_ip.public_ip[index(azurerm_public_ip.public_ip.*.name, "${var.cluster_name}-${var.environment}-${pub.value.target}-${var.name_suffix}-${pub.value.name}-pip")].id
    }
  }

  tags = merge(var.default_tags, map("cluster", "${var.cluster_name}-${var.environment}-${var.name_suffix}"))
}

resource "azurerm_lb" "load_balancer_private" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-lb"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.sku

  dynamic "frontend_ip_configuration" {
    iterator = priv
    for_each = var.private_ips  
    content {
      name                          = "${var.cluster_name}-${var.environment}-${priv.value.target}-${var.name_suffix}-${priv.value.name}-frontend"
      private_ip_address_allocation = priv.value.address_allocation
      private_ip_address            = priv.value.address_allocation == "Static" ? priv.value.ip_address : ""
      subnet_id                     = var.subnet_id
    }
  }

  tags = merge(var.default_tags, map("cluster", "${var.cluster_name}-${var.environment}-${var.name_suffix}"))
}

resource "azurerm_lb_backend_address_pool" "address_pool_public" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-addresspool"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_public.id
}

resource "azurerm_lb_backend_address_pool" "address_pool_private" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-addresspool"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_private.id
}

locals {
  lb_ports_private = [for key, value in var.lb_ports: value if value[7] == "private"]
}

locals {
  lb_ports_public = [for key, value in var.lb_ports: value if value[7] == "public"]
}

resource "azurerm_lb_rule" "lb_rule_public" {
  count                          = length(local.lb_ports_public)
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer_public.id
  name                           = element(keys(var.lb_ports), count.index)
  protocol                       = local.lb_ports_public[1]
  frontend_port                  = local.lb_ports_public[0]
  backend_port                   = local.lb_ports_public[2]
  frontend_ip_configuration_name = "${var.cluster_name}-${var.environment}-${local.lb_ports_public[5]}-${var.name_suffix}-${local.lb_ports_public[6]}-frontend"
  enable_floating_ip             = false
  backend_address_pool_id        = azurerm_lb_backend_address_pool.address_pool_public.id
  idle_timeout_in_minutes        = 5
  probe_id                       = element(concat(azurerm_lb_probe.lb_probe_public.*.id, list("")), count.index)
  depends_on                     = [azurerm_lb_probe.lb_probe_public]
}

resource "azurerm_lb_rule" "lb_rule_private" {
  count                          = length(local.lb_ports_private)
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer_private.id
  name                           = element(keys(var.lb_ports), count.index)
  protocol                       = local.lb_ports_private[1]
  frontend_port                  = local.lb_ports_private[0]
  backend_port                   = local.lb_ports_private[2]
  frontend_ip_configuration_name = "${var.cluster_name}-${var.environment}-${local.lb_ports_private[5]}-${var.name_suffix}-${local.lb_ports_private[6]}-frontend"
  enable_floating_ip             = false
  backend_address_pool_id        = azurerm_lb_backend_address_pool.address_pool_private.id
  idle_timeout_in_minutes        = 5
  probe_id                       = element(concat(azurerm_lb_probe.lb_probe_private.*.id, list("")), count.index)
  depends_on                     = [azurerm_lb_probe.lb_probe_private]
}

resource "azurerm_lb_probe" "lb_probe_public" {
  count               = length(local.lb_ports_public)
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_public.id
  name                = element(keys(var.lb_ports), count.index)
  protocol            = local.lb_ports_public[4] != "" ? "http" : "Tcp"
  port                = local.lb_ports_public[3]
  interval_in_seconds = var.lb_probe_interval
  number_of_probes    = var.lb_probe_unhealthy_threshold
  request_path        = local.lb_ports_public[4] != "" ? local.lb_ports_public[4] : ""
}

resource "azurerm_lb_probe" "lb_probe_private" {
  count               = length(local.lb_ports_private)
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_private.id
  name                = element(keys(var.lb_ports), count.index)
  protocol            = local.lb_ports_private[4] != "" ? "http" : "Tcp"
  port                = local.lb_ports_private[3]
  interval_in_seconds = var.lb_probe_interval
  number_of_probes    = var.lb_probe_unhealthy_threshold
  request_path        = local.lb_ports_private[4] != "" ? local.lb_ports_private[4] : ""
}
