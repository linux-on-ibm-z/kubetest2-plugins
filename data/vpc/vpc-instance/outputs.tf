output "vpc_id" {
  value = local.vpc_id
}

output "subnet_id" {
  value = ibm_is_subnet.primary.id
}

output "security_group_id" {
  value = local.security_group
}
