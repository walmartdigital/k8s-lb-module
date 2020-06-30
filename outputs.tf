output "load_balancer_public_ip" {
  value = azurerm_public_ip.public_ip.*.ip_address
}

output "load_balancer_private_ip" {
  value = azurerm_lb.load_balancer_private.private_ip_address
}

output "lb_address_pool_id_public" {
  value = "${length(azurerm_lb_backend_address_pool.address_pool_public) > 0 ? azurerm_lb_backend_address_pool.address_pool_public[0].id : ''}"
}

output "lb_address_pool_id_private" {
  value = azurerm_lb_backend_address_pool.address_pool_private.id
}
