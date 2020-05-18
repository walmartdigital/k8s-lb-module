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

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

resource "azurerm_lb" "load_balancer_public" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-lb-public"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.sku

  dynamic "frontend_ip_configuration" {
    iterator = pub
    for_each = azurerm_public_ip.public_ip
    content {
      name                          = "${pub.key}-frontend"
      public_ip_address_id          = pub.value.id
    }
  }

  tags = merge(var.default_tags, map("cluster", "${var.cluster_name}-${var.environment}-${var.name_suffix}"))

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

resource "azurerm_lb" "load_balancer_private" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-lb-private"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.sku

  dynamic "frontend_ip_configuration" {
    iterator = priv
    for_each = var.private_ips  
    content {
      name                          = "${var.cluster_name}-${var.environment}-${priv.value.target}-${var.name_suffix}-${priv.value.name}-pip-frontend"
      private_ip_address_allocation = priv.value.address_allocation
      private_ip_address            = priv.value.address_allocation == "Static" ? priv.value.ip_address : ""
      subnet_id                     = var.subnet_id
    }
  }

  tags = merge(var.default_tags, map("cluster", "${var.cluster_name}-${var.environment}-${var.name_suffix}"))

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

resource "azurerm_lb_backend_address_pool" "address_pool_public" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-addresspool"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_public.id

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

resource "azurerm_lb_backend_address_pool" "address_pool_private" {
  name                = "${var.cluster_name}-${var.environment}-${var.target}-${var.name_suffix}-addresspool"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_private.id

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

locals {
  lb_ports_private = [for v in var.lb_ports: v if v.visibility == "private"]
}

locals {
  lb_ports_public = [for v in var.lb_ports: v if v.visibility == "public"]
}

resource "azurerm_lb_rule" "lb_rule_public" {
  count                          = length(local.lb_ports_public)
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer_public.id
  name                           = local.lb_ports_public[count.index].name
  protocol                       = local.lb_ports_public[count.index].protocol
  frontend_port                  = local.lb_ports_public[count.index].port
  backend_port                   = local.lb_ports_public[count.index].lb_rule_port_kube_dns
  frontend_ip_configuration_name = "${var.cluster_name}-${var.environment}-${local.lb_ports_public[count.index].target}-${var.name_suffix}-${local.lb_ports_public[count.index].frontend}-frontend"
  enable_floating_ip             = false
  backend_address_pool_id        = azurerm_lb_backend_address_pool.address_pool_public.id
  idle_timeout_in_minutes        = 5
  probe_id                       = element(concat(azurerm_lb_probe.lb_probe_public.*.id, list("")), count.index)
  depends_on                     = [azurerm_lb_probe.lb_probe_public]

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

resource "azurerm_lb_rule" "lb_rule_private" {
  count                          = length(local.lb_ports_private)
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer_private.id
  name                           = local.lb_ports_private[count.index].name
  protocol                       = local.lb_ports_private[count.index].protocol
  frontend_port                  = local.lb_ports_private[count.index].port
  backend_port                   = local.lb_ports_private[count.index].lb_rule_port_kube_dns
  frontend_ip_configuration_name = "${var.cluster_name}-${var.environment}-${local.lb_ports_private[count.index].target}-${var.name_suffix}-${local.lb_ports_private[count.index].frontend}-frontend"
  enable_floating_ip             = false
  backend_address_pool_id        = azurerm_lb_backend_address_pool.address_pool_private.id
  idle_timeout_in_minutes        = 5
  probe_id                       = element(concat(azurerm_lb_probe.lb_probe_private.*.id, list("")), count.index)
  depends_on                     = [azurerm_lb_probe.lb_probe_private]

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

resource "azurerm_lb_probe" "lb_probe_public" {
  count               = length(local.lb_ports_public)
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_public.id
  name                = var.lb_ports[count.index].name
  protocol            = local.lb_ports_public[count.index].health != "" ? "http" : "Tcp"
  port                = local.lb_ports_public[count.index].lb_rule_port_kube_dns_probe
  interval_in_seconds = var.lb_probe_interval
  number_of_probes    = var.lb_probe_unhealthy_threshold
  request_path        = local.lb_ports_public[count.index].health != "" ? local.lb_ports_public[count.index].health : ""

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}

resource "azurerm_lb_probe" "lb_probe_private" {
  count               = length(local.lb_ports_private)
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer_private.id
  name                = var.lb_ports[count.index].name
  protocol            = local.lb_ports_private[count.index].health != "" ? "http" : "Tcp"
  port                = local.lb_ports_private[count.index].lb_rule_port_kube_dns_probe
  interval_in_seconds = var.lb_probe_interval
  number_of_probes    = var.lb_probe_unhealthy_threshold
  request_path        = local.lb_ports_private[count.index].health != "" ? local.lb_ports_private[count.index].health : ""

  lifecycle {
    ignore_changes = var.ignore_changes
  }
}
