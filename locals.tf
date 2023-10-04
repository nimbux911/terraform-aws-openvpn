locals {
    tags = merge(var.tags, {
        Name = var.stack_name
    })
    ssm_parameters_input = var.ssm_parameters_path == "" ? var.stack_name : var.ssm_parameters_path
    ssm_parameters_path =  substr(local.ssm_parameters_input, -1, -1) == "/" ? local.ssm_parameters_input : "${local.ssm_parameters_input}/"
    
    docker_compose = templatefile("${path.module}/resources/templates/docker-compose.yaml.tpl", { compose_cidr = var.compose_cidr })
    create_client  = file("${path.module}/resources/scripts/create_client.sh")
    revoke_client  = file("${path.module}/resources/scripts/revoke_client.sh")
}