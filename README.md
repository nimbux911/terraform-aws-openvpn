# AWS OpenVPN Terraform module

Terraform module which creates an OpenVPN EC2 instance in AWS.

## Usage

#### Terraform required version >= 0.14.8

## OpenVPN Service

```hcl
module "openvpn" {
  source            = "github.com/nimbux911/terraform-aws-openvpn.git?ref=vpNegro"
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
| project | Name of the project where the VPN will be used | `string` | `""` | yes |
| vpc\_id | VPC ID where openvpn will be deployed. | `string` | `""` | yes |
| ami\_id | AMI ID of the same region where the instance will be deployed | `string` | `""` | yes |
| instance\_type | The type that will be used on the instance | `string` | `""` | yes |
| subnets\_ids | Public subnets ids of the instance where the openvpn will be deployed | `list[string]` | `[]` | yes |
| peered_networks | CIDRs which will be pushed by the openvpn | `string` | `""` | yes |
| docker_cidr | CIDR which will be used by docker service inside the instance | `list[string]` | `[]` | yes |
| compose_cidr | CIDR which will be used by docker-compose.yaml file inside the instance | `list[string]` | `[]` | yes |
