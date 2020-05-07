variable "resource_group" {
  type = string
}

variable "lb_type" {
  type    = string
  default = "public"
}

variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "name_suffix" {
  type = string
}

variable "target" {
  type = string
  default = "workers"
}

variable "sku" {
  type = string
  default = "Basic"
}

variable "lb_ports" {
  type    = map(list(string))
  default = {}
}

variable "public_ips" {
  type    = map(list(string))
  default = {}
}

variable "private_ips" {
  type    = map(list(string))
  default = {}
}

variable "lb_probe_interval" {
  type    = string
  default = 5
}

variable "lb_probe_unhealthy_threshold" {
  type    = string
  default = 2
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "frontend_private_ip_address_allocation" {
  type    = string
  default = "Dynamic"
}

variable "frontend_private_ip_address" {
  type    = string
  default = ""
}

variable "default_tags" {
  type = map
  default = {}
}
