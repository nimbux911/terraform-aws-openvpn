# AWS OpenVPN Terraform module

Terraform module which creates an OpenVPN EC2 instance in AWS.

![OpenVPN Version](https://img.shields.io/badge/OpenVPN-2.6.20-blue?style=for-the-badge)
![Alpine Version](https://img.shields.io/badge/Alpine-3.21.3-orange?style=for-the-badge)
![Terraform Version](https://img.shields.io/badge/Terraform-%3E%3D%200.14.8-purple?style=for-the-badge)

## OpenVPN Service

```hcl
module "openvpn" {
    source              = "github.com/nimbux911/terraform-aws-openvpn.git"
    stack_name          = "${var.env}-openvpn"
    vpc_id              = "vpc-abcde12345"
    instance_type       = "t3.small"
    subnet_id           = "subnet-abcde12345"
    peered_networks     = ["172.16.0.0/16", "172.17.0.0/16"]
    tags                = local.common_tags
    ssm_parameters_path = "/terraform/ec2-openvpn/"
    ssh_ingress_cidrs   = ["123.22.12.53/32"]
}
```

By default, the module selects the latest Canonical Ubuntu 26.04 LTS AMI. Set `ubuntu_ami_id` to pin a custom AMI.

Launch template changes trigger an Auto Scaling Group instance refresh. The module runs a single OpenVPN instance, so AMI and user-data changes can cause VPN downtime while the instance is replaced.

## DNS

The module can point a DNS record at the OpenVPN Elastic IP. Route53 is the default DNS provider; Cloudflare is also supported.

```hcl
module "openvpn" {
    source        = "github.com/nimbux911/terraform-aws-openvpn.git"
    stack_name    = "prod-openvpn"
    vpc_id        = "vpc-abcde12345"
    subnet_id     = "subnet-abcde12345"
    dns_name      = "vpn.example.com"
    dns_provider  = "cloudflare"
    dns_zone_name = "example.com"
}
```

OpenVPN client profiles use `dns_name` as the remote endpoint when it is set; otherwise they use the module Elastic IP.

## Access Control

The module can manage per-user access control through AWS Systems Manager. When enabled, `vpn_users` is the source of truth: users removed from this map are revoked with `ovpn_revokeclient`, their CCD file is deleted, and their firewall permissions are removed.

```hcl
module "openvpn" {
    source                    = "github.com/nimbux911/terraform-aws-openvpn.git"
    stack_name                = "prod-openvpn"
    vpc_id                    = "vpc-abcde12345"
    subnet_id                 = "subnet-abcde12345"
    peered_networks           = ["10.0.0.0/8"]
    enable_vpn_access_control = true
    vpn_client_cidr           = "192.168.255.0/24"

    vpn_access_groups = {
        admin = {
            allowed_cidrs = ["10.0.0.0/8"]
        }
        dev = {
            allowed_cidrs = ["10.20.0.0/16", "10.30.5.0/24"]
        }
    }

    vpn_users = {
        alice = {
            group = "admin"
            ip    = "192.168.255.10"
        }
        bob = {
            group = "dev"
            ip    = "192.168.255.11"
        }
    }
}
```

Access control changes are applied by an SSM association after `terraform apply`; the instance is not restarted. Existing connected users may need to reconnect only when their fixed VPN IP changes.

OpenVPN does not push a default route, so client internet traffic continues using the client's local gateway. ACLs only affect traffic routed through the VPN to `peered_networks`.

When access control is enabled, the SSM document creates missing client certificates and `.ovpn` profiles for users in `vpn_users`, writes CCD fixed-IP files, revokes removed users, and applies firewall rules inside the OpenVPN container before NAT. `create_client.sh` is still available for manual client creation when access control is disabled.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| compose\_cidr | CIDR for default compose network. | `string` | `"192.168.127.0/24"` | no |
| cloudflare\_dns\_proxied | Whether Cloudflare should proxy the OpenVPN DNS record. OpenVPN should normally leave this false. | `bool` | `false` | no |
| docker\_cidr | CIDR for default docker network. | `string` | `"192.168.125.0/24"` | no |
| dns\_name | Optional DNS name to point at the OpenVPN Elastic IP. No DNS record is created when empty. | `string` | `""` | no |
| dns\_provider | DNS provider used for dns\_name. Valid values: route53, cloudflare. | `string` | `"route53"` | no |
| dns\_zone\_id | Optional DNS zone ID. Route53 hosted zone ID or Cloudflare zone ID, depending on dns\_provider. | `string` | `""` | no |
| dns\_zone\_name | DNS zone name used to look up the hosted zone when dns\_zone\_id is empty. | `string` | `""` | no |
| instance\_type | OpenVPN EC2 instance type. | `string` | `"t3a.micro"` | no |
| openvpn\_image | Docker image used to run OpenVPN. | `string` | `"public.ecr.aws/w6z0u0b2/nimbux911/dockovpn:2.6.20-config.0.1.0"` | no |
| peered\_networks | CIDRs blocks which OpenVPN will be able to route the traffic to/from. | `list(string)` | `[]` | no |
| ssh\_ingress\_cidrs | CIDR blocks to allow ssh access to the OpenVPN instance. | `list(string)` | `[]` | no |
| ssm\_parameters\_path | Path prefix for ssm parameters. | `string` | `""` | no |
| stack\_name | Name for the stack resources. | `string` | `"openvpn"` | no |
| subnet\_id | Public subnet id to host the OpenVPN instance. | `string` | ` ` | yes |
| tags | Tags to add to the stack resources. | `map` | `{}` | no |
| ubuntu\_ami\_id | Custom Ubuntu AMI id for the OpenVPN instance. | `string` | `""` | no |
| volume\_path | Path to mount the data fs. | `string` | `"/openvpn/"` | no |
| vpc\_id | VPC id where the OpenVPN will be hosted. | `string` | ` ` | yes |
| backup_schedule | A backup schedule defines the frequency and timing of data backups. | `string` | ` ` | no |
| backup_retention | Backup retention refers to the rules that determine how long backups are stored before being deleted. The unit is days | `number` | ` ` | no |
| ebs_snapshot_id | The EBS snapshot ID | `string` | ` ` | no |
| enable\_vpn\_access\_control | Enable per-user OpenVPN access control managed through SSM. | `bool` | `false` | no |
| vpn\_client\_cidr | CIDR used by OpenVPN clients when access control is enabled. | `string` | `"192.168.255.0/24"` | no |
| vpn\_access\_groups | Access groups mapped to destination CIDRs allowed through the VPN. | `map(object({ allowed_cidrs = list(string) }))` | `{}` | no |
| vpn\_users | OpenVPN users mapped to access groups and fixed VPN IPs. Removed users are revoked when access control is enabled. | `map(object({ group = string, ip = string }))` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| autoscaling\_group\_id | The ID of the autoscaling group. |
| data\_volume\_id | The ID of the data EBS volume. |
| eip\_public\_ip | The public address of the eip. |
| iam\_role\_arn | The instance role ARN. |
| security\_group\_id | The ID of the security group. |
