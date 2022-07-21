variable "environment" {}
variable "project" {}
variable "vpc_id" {}
variable "subnet_ids" {}
variable "ami_id" {} # Ubuntu 22.04 LTS
variable "instance_type" {}
variable "peered_networks" {}
variable "docker_cidr" { description = "IP docker"}
variable "compose_cidr" { description = "IP docker-compose"}
