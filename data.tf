data "aws_region" "current" {}
data "template_file" "docker_compose" {
  template = "${file("${path.module}/resources/templates/docker-compose.yaml.tftpl")}"
  vars = {
    docker_cidr = var.docker_cidr
  }
}