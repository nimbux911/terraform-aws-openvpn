# AWS OpenVPN Terraform module

Terraform module which creates an OpenVPN EC2 instance in AWS.

![OpenVPN Version](https://img.shields.io/badge/OpenVPN-2.6.20-blue?style=for-the-badge)
![Alpine Version](https://img.shields.io/badge/Alpine-3.21.3-orange?style=for-the-badge)
![Terraform Version](https://img.shields.io/badge/Terraform-%3E%3D%201.3-purple?style=for-the-badge)

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

The module can manage per-user access control through AWS Systems Manager. With `enable_vpn_access_control = true` and the default `vpn_profile_management_mode = "authoritative"`, `vpn_users` is the source of truth: users removed from this map are revoked with `ovpn_revokeclient`, their CCD file is deleted, and their firewall permissions are removed. **Do not use authoritative mode to adopt an incomplete inventory of an existing VPN.**

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

For a new instance, run the first `terraform apply` with `vpn_users = {}` so the EC2 bootstrap can finish creating the OpenVPN configuration and starting the container. After cloud-init completes, add users to `vpn_users` and run a second `terraform apply` to let the SSM association generate profiles and apply access-control rules. This avoids the SSM association running before OpenVPN files are ready during first boot.

### Additive adoption and client-to-client testing

Set `enable_vpn_access_control = true` and `vpn_profile_management_mode = "additive"` to use a separate, non-destructive SSM script:

- Existing certificates, private keys, `.ovpn` files and CCDs are preserved. Unknown clients are never revoked or deleted, even if omitted from `vpn_users`.
- Omit `ip` when adopting a dynamically addressed client. Existing fixed-IP clients must retain their current address; mismatches abort the sync rather than changing it.
- Revoked/expired identities are not recreated. Use the exact, case-sensitive common name of each valid certificate, not the filename of a stale profile.
- The full desired inventory is checked before issuing certificates. New fixed addresses must be outside the running server's dynamic pool, unreserved in other CCDs and unused in its status file. For `server 192.168.255.0 255.255.255.0` with `topology subnet` and no explicit pool, the implicit pool is `.2` through `.253`; `.254` is outside it.
- No firewall commands, server configuration changes, container lifecycle operations or VPN restart are performed. Existing ACLs remain untouched; `group` does not enforce new permissions in this mode.
- Missing profiles are written atomically with mode `0600`; their contents are never printed to SSM output or stored in Terraform state. A host-level lock prevents overlapping additive runs. Requires Bash, `flock`, Docker, and the image's existing EasyRSA/OpenSSL utilities.
- The association pins the SSM document version, so an updated document is selected on the next apply.

```hcl
enable_vpn_access_control   = true
vpn_profile_management_mode = "additive"
vpn_access_groups = { existing = { allowed_cidrs = [] } }
vpn_users = {
  existing_dynamic_client = { group = "existing" }
  existing_fixed_client   = { group = "existing", ip = "192.168.255.11" }
  test_mac                = { group = "existing", ip = "192.168.255.254" }
}
```

This adopts certificate identities into configuration; certificates are not separate Terraform resources and no `terraform import` is needed. Taking a profile out of an additive map **does not revoke it**. Explicitly revoke temporary certificates when the test is over, verify CRL enforcement, and remove their profile/CCD separately. Switching back to authoritative mode requires a complete inventory with fixed IPs and a separate review of the firewall/revocation impact.

With server-side kernel forwarding already enabled, clients may communicate through `tun0` without OpenVPN's `client-to-client` directive. Additive mode does not enable forwarding or guarantee isolation: verify actual reachability from two clients. It also does not repair missing existing ACLs.

For this feature alone, a reviewed Terraform plan must not change the launch template, ASG, instance, user-data, image or networking. Changing the module source to a local checkout does not itself require replacement, but unrelated drift in a full plan can still be disruptive.

Offline script regression tests (all Docker calls mocked; no AWS requests):

```bash
python3 -m unittest discover -s tests -v
```

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
| vpn\_profile\_management\_mode | `authoritative` manages revocation/ACLs; `additive` preserves existing profiles and firewall rules. | `string` | `"authoritative"` | no |
| vpn\_client\_cidr | CIDR used by OpenVPN clients when access control is enabled. | `string` | `"192.168.255.0/24"` | no |
| vpn\_access\_groups | Access groups mapped to destination CIDRs allowed through the VPN. | `map(object({ allowed_cidrs = list(string) }))` | `{}` | no |
| vpn\_users | Case-sensitive client names mapped to groups and optional fixed IPs. Omit `ip` only in additive mode. | `map(object({ group = string, ip = optional(string) }))` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| autoscaling\_group\_id | The ID of the autoscaling group. |
| data\_volume\_id | The ID of the data EBS volume. |
| eip\_public\_ip | The public address of the eip. |
| iam\_role\_arn | The instance role ARN. |
| security\_group\_id | The ID of the security group. |
