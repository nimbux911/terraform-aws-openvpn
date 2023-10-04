data "aws_region" "current" {}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

data "aws_ami" "ubuntu" {
    count       = var.ubuntu_ami_id != "" ? 0 : 1
    most_recent = true
    owners      = ["amazon"]

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
    }

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }
}
