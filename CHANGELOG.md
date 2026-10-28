## [2.6.0] - 2026-10-28

- Add optional `vpn_runtime_config` to manage the dynamic IP pool and UDP receive buffer through SSM, without changing user-data or replacing the instance. Defaults to `null` for existing callers.
- Validate pool/CCD conflicts and container compatibility, back up changed configuration, restart only the OpenVPN container, and attempt rollback if startup fails. Matching settings do not trigger a restart; certificates, keys, profiles and CCDs are preserved.
- Reject runtime changes with authoritative ACL management or unsupported custom firewall/NAT rules to avoid losing policy on restart.
- Fix additive profile validation for explicit dynamic pools when `server` uses `nopool`.
- Add offline safety regression tests for configuration changes, profile preservation, idempotency and recovery.

## [2.5.0] - 2026-10-19

- Add opt-in `vpn_profile_management_mode = "additive"` for SSM-managed adoption of existing clients and creation of dedicated fixed-IP service profiles, without VPN restart, user-data changes or firewall changes. The default remains `authoritative` for existing callers.
- Preserve existing certificates, private keys, exported profiles and CCD files in additive mode. Clients omitted from `vpn_users` are not revoked or deleted; removal requires explicit revocation.
- Make `vpn_users.ip` optional in additive mode to retain existing dynamic address allocation. Authoritative mode still requires fixed client IPs.
- Validate the complete desired inventory before creating profiles: reject revoked or expired identities, changes to existing fixed addresses, and new fixed-IP conflicts with the dynamic pool, other CCDs or active sessions.
- Serialize additive sync runs with a host-level lock and write new profiles atomically with restricted permissions, without printing their private keys to SSM output or storing them in Terraform state.
- Explicitly select the SSM document version in its association so updated scripts are used on subsequent applies.
- Require Terraform 1.3 or newer for optional object attributes and document additive migration and client-to-client connectivity using existing kernel forwarding.

## [2.4.0] - 2026-06-12

- Update the default Ubuntu AMI lookup to Canonical Ubuntu 26.04 LTS images.
- Add DNS record management for Route53 and Cloudflare through `dns_name` and related inputs.
- Improve EC2 bootstrap reliability with IMDSv2 metadata lookups, EBS NVMe serial-based device detection, explicit Docker image pulls, and longer PKI initialization timeout.
- Add SSM-managed OpenVPN access control with fixed client IPs, generated profiles, user revocation, CCD files, and container-level firewall rules enforced before OpenVPN NAT.
- Add ASG instance refresh so launch template changes replace the singleton OpenVPN instance.

## [2.3.0] -  2025-03-31

- Add EBS volume backup.
- Add EBS volume restore.

## [2.2.0] - 2025-03-11

- The open vpn version was updated to 2.6.12 and the Alpine version of the container was updated to 3.21.3.

## [2.1.2] - 2025-01-15

- Docker and compose CIDRs were fixed.
- Removed the 'version' attribute from docker-compose.yml as it is deprecated.

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
