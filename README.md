# AWS OpenVPN Terraform module

Terraform module which creates an openVPN on AWS.

## Usage

#### Terraform required version >= 0.14.8

## OpenVPN Service

```hcl
module "openvpn" {
  source            = "github.com/nimbux911/terraform-aws-openvpn.git?ref=vpNegro"
  environment       = "ops"
  vpc_id            = "vpc-04fdf81f6998d2d48"
  subnet_ids        = ["subnet-01a3f5a6b3231570f", "subnet-03310ccc0e2c89072", "subnet-02acbaf7116d9c1a9"]
  peered_networks   = ["172.16.0.0/16", "172.17.0.0/16"]
  docker_cidr       = "10.100.0.1/16"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name of the resources. | `string` | `""` | yes |
| vpc\_id | VPC ID where openvpn will be deployed. | `string` | `""` | yes |
| subnets\_ids | Public subnets ids of the instance where the openvpn will be deployed | `list[string]` | `[]` | yes |
| peered_networks | CIDRs which will be pushed by the openvpn | `string` | `""` | yes |
| docker_cidr | CIDR which will be used by docker service inside the instance | `list[string]` | `[]` | yes |
