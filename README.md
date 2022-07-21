# AWS OpenVPN Terraform module

Terraform module which creates an OpenVPN EC2 instance in AWS.

## Usage

#### Terraform required version >= 0.14.8

## OpenVPN Service

```hcl
module "openvpn" {
  source            = "github.com/nimbux911/terraform-aws-openvpn.git?ref=main"
  environment       = "ops"
  project           = "project-name"
  vpc_id            = "vpc-04fdf81f6998d2d48"
  ami_id            = "ami-052efd3df9dad4825"
  instance_type     = "t3a.micro"
  subnet_ids        = ["subnet-01a3f5a6b3231570f", "subnet-03310ccc0e2c89072", "subnet-02acbaf7116d9c1a9"]
  peered_networks   = ["172.16.0.0/16", "172.17.0.0/16"]
  docker_cidr       = "10.100.0.1/16"
  compose_cidr      = "192.168.100.1/24"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name of the resources. | `string` | `""` | yes |
| project | Name of the project where the VPN will be used. | `string` | `""` | yes |
| vpc\_id | VPC ID where OpenVPN will be deployed. | `string` | `""` | yes |
| ami\_id | AMI ID to user for the OpenVPN EC2 instance. | `string` | `""` | yes |
| instance\_type | OpenVPN EC2 instance type. | `string` | `""` | yes |
| subnet\_ids | Public subnet ids from the designed VPC. | `list[string]` | `[]` | yes |
| peered_networks | CIDRs blocks which OpenVPN will be able to route the traffic to/from. | `string` | `""` | yes |
| docker_cidr | CIDR for Docker service. | `list[string]` | `[]` | yes |
| compose_cidr | CIDR for `docker-compose.yaml`. | `list[string]` | `[]` | yes |
