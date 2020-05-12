# Azure Load Balancer Module

This module create all required resources for deploy a public and a private load balancer on Azure. If more tnah one ip and load balancer its needed
** USE STANDARD SKU**.

## Usage

### Create a public load balancer

```bash
module "az_lb" {
  source = "git::https://github.com/walmartdigital/k8s-lb-module.git?ref=0.1.0"

  resource_group = "my-resource-group"
  cluster_name   = "my-cluster-name"
  environment    = "staging"
  name_suffix    = "abc123"

  lb_ports = {
    http  = ["80", "Tcp", "80", "80"]
    https = ["443", "Tcp", "443", "443"]
  }
}
```

### Create a private load balancer with public and private ips

First its needed define the ips that will be used by the load balancer rules. They can be as many public and private ips as are needed:

```yaml
  public_ips = {
    cockroach = {
      name = "cockroach"
      target = "workers"
    }
  }

  private_ips = {
    dns = {
      name = "dns"
      target = "workers"
      address_allocation = "Dynamic"
      ip_address = ""
    }
  }
```

The must be added the load balancer rules and set the visibility and the ip (frontend) that will be used:

```yaml
  lb_ports = [
    {
      name = "dns"
      port = "53"
      protocol = "Udp"
      lb_rule_port_kube_dns = data.consul_keys.input.var.lb_rule_port_kube_dns
      lb_rule_port_kube_dns_probe = data.consul_keys.input.var.lb_rule_port_kube_dns_probe
      health = ""
      target = "workers"
      frontend = "dns"
      visibility = "private"
    },
    {
      name = "grpc"
      port = "26257"
      protocol = "Tcp"
      lb_rule_port_kube_dns = data.consul_keys.input.var.lb_rule_port_grpc
      lb_rule_port_kube_dns_probe = data.consul_keys.input.var.lb_rule_port_grpc
      health = ""
      target = "workers"
      frontend = "cockroach"
      visibility = "public"
    },
    {
      name = "http"
      port = "8080"
      protocol = "Tcp"
      lb_rule_port_kube_dns = data.consul_keys.input.var.lb_rule_port_http
      lb_rule_port_kube_dns_probe = data.consul_keys.input.var.lb_rule_port_http
      health =  "/health"
      target = "workers"
      frontend = "cockroach"
      visibility = "public"
    }
  ]
```

## Arguments

* **resource_group**: A string representing the resource group where all resources will be provisioned, this resource group needs to be previously created (required).
* **cluster_name**: A string used as the cluster name.
* **environment**: A string used as environment where the cluster is deployed.
* **name_suffix**: A string used as name suffix.
* **lb_type**: A string used as the load balancer type. Default is public. If the load balancer type is private, you need to provide the following string variables: _subnet_id_ (required), _frontend_private_ip_address_allocation_ (optional) and _frontend_private_ip_address_ (optional).
* **lb_ports**: A list of map used to provide the load balancer rules, each item is a list, and the value is a map with the following fields:

  - name
  - port
  - protocol
  - lb_rule_port_kube_dns
  - lb_rule_port_kube_dns_probe
  - health
  - target
  - frontend
  - visibility

## Outputs

* **load_balancer_public_ip**: The load balancer public IP.
* **load_balancer_private_ip**: The load balancer private IP.
* **lb_address_pool_id**: The load balancer address pool ID.