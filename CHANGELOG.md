## [2.1.1] - 2025-01-03

- Add /dev/net/tun device to Docker Compose config for OpenVPN compatibility. Recent changes in Docker require explicitly mounting the /dev/net/tun device to ensure proper operation of OpenVPN. Updated docker-compose.yml to include this configuration.

## [2.1.0] - 2024-04-16

- Change DockerOVPN source for the one forked by nimbux which also contains Openvpn community 2.6.8
- Add "EASYRSA_BATCH=1" hardcoded variable to docker-compose to allow for auto-run in the initpki script

## [2.0.0] - 2023-10-04

- Replace s3 persistent storage with EBS volume
- Replace launch configuration with launch template
- Update Docker version
- Add useful outputs
- Add default values and types for most inputs
- Add tags
- Add fixed version of the openvpn docker image

## [1.1.0] - 2024-07-19

- Add tags input

## [1.0.1] - 2022-07-29

- Add outputs.tf file with security group id.

## [1.0.0] - 2022-07-21

- First version of the OpenVPN module.
