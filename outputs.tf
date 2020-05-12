output "load_balancer_public_ip" {
  value = azurerm_public_ip.public_ip.*.ip_address
}

output "load_balancer_private_ip" {
  value = azurerm_lb.load_balancer.private_ip_address
}

output "lb_address_pool_id" {
  value = azurerm_lb_backend_address_pool.address_pool.id
}
