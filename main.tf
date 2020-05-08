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

resource "azurerm_lb_rule" "lb_rule_public" {
  count                          = length(var.lb_ports_public)
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer_public.id
  name                           = var.lb_ports_public[count.index].name
  protocol                       = var.lb_ports_public[count.index].protocol
  frontend_port                  = var.lb_ports_public[count.index].port
  backend_port                   = var.lb_ports_public[count.index].lb_rule_port_kube_dns
  frontend_ip_configuration_name = "${var.cluster_name}-${var.environment}-${var.lb_ports_public[count.index].target}-${var.name_suffix}-${var.lb_ports_public[count.index].frontend}-frontend"
  enable_floating_ip             = false
  backend_address_pool_id        = azurerm_lb_backend_address_pool.address_pool_public.id
  idle_timeout_in_minutes        = 5
  probe_id                       = element(concat(azurerm_lb_probe.lb_probe_public.*.id, list("")), count.index)
  depends_on                     = [azurerm_lb_probe.lb_probe_public]
}

resource "azurerm_lb_rule" "lb_rule_private" {
  count                          = length(var.lb_ports_private)
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer_private.id
  name                           = var.lb_ports_private[count.index].name
  protocol                       = var.lb_ports_private[count.index].protocol
  frontend_port                  = var.lb_ports_private[count.index].port
  backend_port                   = var.lb_ports_private[count.index].lb_rule_port_kube_dns
  frontend_ip_configuration_name = "${var.cluster_name}-${var.environment}-${var.lb_ports_private[count.index].target}-${var.name_suffix}-${var.lb_ports_private[count.index].frontend}-frontend"
  enable_floating_ip             = false
  backend_address_pool_id        = azurerm_lb_backend_address_pool.address_pool_private.id
  idle_timeout_in_minutes        = 5
  probe_id                       = element(concat(azurerm_lb_probe.lb_probe_private.*.id, list("")), count.index)
  depends_on                     = [azurerm_lb_probe.lb_probe_private]
}

resource "azurerm_lb_probe" "lb_probe_public" {
  count               = length(var.lb_ports_public)
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_public.id
  name                = var.lb_ports_public[count.index].name
  protocol            = var.lb_ports_public[count.index].health != "" ? "http" : "Tcp"
  port                = var.lb_ports_public[count.index].lb_rule_port_kube_dns_probe
  interval_in_seconds = var.lb_probe_interval
  number_of_probes    = var.lb_probe_unhealthy_threshold
  request_path        = var.lb_ports_public[count.index].health != "" ? var.lb_ports_public[count.index].health : ""
}

resource "azurerm_lb_probe" "lb_probe_private" {
  count               = length(var.lb_ports_private)
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_private.id
  name                = var.lb_ports_private[count.index].name
  protocol            = var.lb_ports_private[count.index].health != "" ? "http" : "Tcp"
  port                = var.lb_ports_private[count.index].lb_rule_port_kube_dns_probe
  interval_in_seconds = var.lb_probe_interval
  number_of_probes    = var.lb_probe_unhealthy_threshold
  request_path        = var.lb_ports_private[count.index].health != "" ? var.lb_ports_private[count.index].health : ""
}
