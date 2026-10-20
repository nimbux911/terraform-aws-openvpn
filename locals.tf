locals {
  tags = merge(var.tags, {
    Name = var.stack_name
  })
  ssm_parameters_input = var.ssm_parameters_path == "" ? "/${var.stack_name}/" : var.ssm_parameters_path
  ssm_parameters_path  = substr(local.ssm_parameters_input, -1, -1) == "/" ? local.ssm_parameters_input : "${local.ssm_parameters_input}/"
  vpn_endpoint         = var.dns_name != "" ? var.dns_name : aws_eip.this.public_ip
  docker_compose = templatefile("${path.module}/resources/templates/docker-compose.yaml.tpl", {
    compose_cidr  = var.compose_cidr
    openvpn_image = var.openvpn_image
  })
  create_client = templatefile("${path.module}/resources/scripts/create_client.sh", {
    vpn_endpoint = local.vpn_endpoint
  })
  revoke_client = file("${path.module}/resources/scripts/revoke_client.sh")
  access_control = var.vpn_profile_management_mode == "additive" ? templatefile("${path.module}/resources/scripts/sync_profiles_additive.sh.tpl", {
    volume_path     = var.volume_path
    vpn_endpoint    = local.vpn_endpoint
    vpn_client_cidr = var.vpn_client_cidr
    vpn_users       = var.vpn_users
    }) : templatefile("${path.module}/resources/scripts/apply_access_control.sh.tpl", {
    volume_path       = var.volume_path
    vpn_endpoint      = local.vpn_endpoint
    vpn_client_cidr   = var.vpn_client_cidr
    peered_networks   = var.peered_networks
    vpn_access_groups = var.vpn_access_groups
    vpn_users         = var.vpn_users
  })
}
