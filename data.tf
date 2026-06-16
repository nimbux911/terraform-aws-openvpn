data "aws_region" "current" {}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

data "aws_ami" "ubuntu" {
  count       = var.ubuntu_ami_id != "" ? 0 : 1
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_route53_zone" "dns" {
  count        = var.dns_name != "" && var.dns_provider == "route53" && var.dns_zone_id == "" ? 1 : 0
  name         = var.dns_zone_name
  private_zone = false
}

data "cloudflare_zone" "dns" {
  count = var.dns_name != "" && var.dns_provider == "cloudflare" && var.dns_zone_id == "" ? 1 : 0

  filter = {
    name = var.dns_zone_name
  }
}
