# Fetch existing VPC if `vpc_name` is provided
data "ibm_is_vpc" "existing_vpc" {
  count = var.vpc_name != "" ? 1 : 0
  name  = var.vpc_name
}

# Fetch existing subnet if `vpc_name` and `vpc_subnet_name` are provided
data "ibm_is_subnet" "existing_subnet" {
  count = var.vpc_name != "" && var.vpc_subnet_name != "" ? 1 : 0
  name  = var.vpc_subnet_name
}

# Fetch resource group
data "ibm_resource_group" "default_group" {
  name = var.vpc_resource_group
}

# Create a new VPC and associated components only if no valid existing VPC is provided
resource "ibm_is_vpc" "vpc" {
  count                       = var.vpc_name == "" || length(data.ibm_is_vpc.existing_vpc) == 0 ? 1 : 0
  name                        = var.vpc_name == "" ? "${var.cluster_name}-vpc" : var.vpc_name
  resource_group              = data.ibm_resource_group.default_group.id
  default_security_group_name = "${var.cluster_name}-security-group"
}

resource "ibm_is_subnet" "subnet" {
  count                    = var.vpc_name == "" || length(data.ibm_is_vpc.existing_vpc) == 0 ? 1 : 0
  name                     = "${var.cluster_name}-subnet"
  vpc                      = ibm_is_vpc.vpc[0].id
  zone                     = var.vpc_zone
  resource_group           = data.ibm_resource_group.default_group.id
  total_ipv4_address_count = 256
}

resource "ibm_is_floating_ip" "gateway" {
  name           = "${var.cluster_name}-gateway-ip"
  zone           = var.vpc_zone
  resource_group = data.ibm_resource_group.default_group.id
}

resource "ibm_is_public_gateway" "gateway" {
  name           = "${var.cluster_name}-gateway"
  vpc            = ibm_is_vpc.vpc[0].id
  zone           = var.vpc_zone
  resource_group = data.ibm_resource_group.default_group.id
  floating_ip = {
    id = ibm_is_floating_ip.gateway.id
  }
}

# Define security group rules (always create them for new VPCs)
resource "ibm_is_security_group_rule" "primary_outbound" {
  group     = ibm_is_vpc.vpc[0].default_security_group
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

resource "ibm_is_security_group_rule" "primary_inbound" {
  group     = ibm_is_vpc.vpc[0].default_security_group
  direction = "inbound"
  remote    = ibm_is_vpc.vpc[0].default_security_group
}

resource "ibm_is_security_group_rule" "primary_ssh" {
  group     = ibm_is_vpc.vpc[0].default_security_group
  direction = "inbound"
  remote    = "0.0.0.0/0"

  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "primary_ping" {
  group     = ibm_is_vpc.vpc[0].default_security_group
  direction = "inbound"
  remote    = "0.0.0.0/0"

  icmp {
    code = 0
    type = 8
  }
}

resource "ibm_is_security_group_rule" "primary_api_server" {
  group     = ibm_is_vpc.vpc[0].default_security_group
  direction = "inbound"
  remote    = "0.0.0.0/0"

  tcp {
    port_min = 992
    port_max = 992
  }
}

# Local values for determining VPC and Subnet IDs
locals {
  vpc_id = var.vpc_name != "" && length(data.ibm_is_vpc.existing_vpc) > 0 ? data.ibm_is_vpc.existing_vpc[0].id : ibm_is_vpc.vpc[0].id

  subnet_id = var.vpc_name != "" && length(data.ibm_is_subnet.existing_subnet) > 0 ? data.ibm_is_subnet.existing_subnet[0].id : ibm_is_subnet.subnet[0].id

  security_group_id = var.vpc_name != "" && length(data.ibm_is_vpc.existing_vpc) > 0 ? data.ibm_is_vpc.existing_vpc[0].default_security_group : ibm_is_vpc.vpc[0].default_security_group
}

# Fetch image for instance template
data "ibm_is_image" "node_image" {
  name = var.node_image
}

# Fetch SSH key
data "ibm_is_ssh_key" "ssh_key" {
  name = var.vpc_ssh_key
}

# Instance template for nodes
resource "ibm_is_instance_template" "node_template" {
  name           = "${var.cluster_name}-node-template"
  image          = data.ibm_is_image.node_image.id
  profile        = var.node_profile
  vpc            = local.vpc_id
  zone           = var.vpc_zone
  resource_group = data.ibm_resource_group.default_group.id
  keys           = [data.ibm_is_ssh_key.ssh_key.id]

  primary_network_interface {
    subnet          = local.subnet_id
    security_groups = [ibm_is_vpc.vpc[0].default_security_group]
  }
}

# Master node module
module "master" {
  source                    = "./node"
  node_name                 = "${var.cluster_name}-master"
  node_instance_template_id = ibm_is_instance_template.node_template.id
  resource_group            = data.ibm_resource_group.default_group.id
}

# Worker nodes module
module "workers" {
  source                    = "./node"
  count                     = var.workers_count
  node_name                 = "${var.cluster_name}-worker-${count.index}"
  node_instance_template_id = ibm_is_instance_template.node_template.id
  resource_group            = data.ibm_resource_group.default_group.id
}

resource "null_resource" "wait-for-master-completes" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = module.master.public_ip
    private_key = file(var.ssh_private_key)
    timeout     = "20m"
  }
  provisioner "remote-exec" {
    inline = [
      "cloud-init status -w"
    ]
  }
}

resource "null_resource" "wait-for-workers-completes" {
  count = var.workers_count
  connection {
    type        = "ssh"
    user        = "root"
    host        = module.workers[count.index].public_ip
    private_key = file(var.ssh_private_key)
    timeout     = "15m"
  }
  provisioner "remote-exec" {
    inline = [
      "cloud-init status -w"
    ]
  }
}
