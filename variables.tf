variable "aws_region" {}
variable "environment" {}
variable "vpc_id" {}
variable "ami_id" { default = "ami-02f3416038bdb17fb" } # Ubuntu 22.04 LTS
variable "instance_type" { default = "t3a.micro" }
variable "peered_networks" {}
variable "docker_cidr" {}
