variable "compose_cidr" {
  type    = string
  default = "192.168.127.0/24"
}
variable "docker_cidr" {
  type    = string
  default = "192.168.125.0/24"
}
variable "openvpn_image" {
  description = "Docker image used to run OpenVPN."
  type        = string
  default     = "public.ecr.aws/w6z0u0b2/nimbux911/dockovpn:2.6.20-config.0.1.0"
}
variable "instance_type" {
  type    = string
  default = "t3a.micro"
}
variable "peered_networks" {
  type    = list(string)
  default = []
}
variable "ssh_ingress_cidrs" {
  type    = list(string)
  default = []
}
variable "ssm_parameters_path" {
  type    = string
  default = ""
}
variable "stack_name" {
  type    = string
  default = "openvpn"
}
variable "subnet_id" {
  type = string
}
variable "tags" {
  type    = map(any)
  default = {}
}
variable "ubuntu_ami_id" {
  type    = string
  default = ""
}
variable "volume_path" {
  type    = string
  default = "/openvpn/"
}
variable "vpc_id" {
  type = string
}

variable "backup_schedule" {
  default = "cron(0 5 * * ? *)"
}

variable "backup_retention" {
  description = "The unit is days"
  default     = 7
}

variable "ebs_snapshot_id" {
  description = "EBS snapshot id to restore"
  default     = null
}

variable "dns_name" {
  description = "Optional DNS name to point at the OpenVPN Elastic IP. No DNS record is created when empty."
  type        = string
  default     = ""
}

variable "dns_provider" {
  description = "DNS provider used for dns_name. Valid values: route53, cloudflare."
  type        = string
  default     = "route53"

  validation {
    condition     = contains(["route53", "cloudflare"], var.dns_provider)
    error_message = "dns_provider must be either route53 or cloudflare."
  }
}

variable "dns_zone_name" {
  description = "DNS zone name used to look up the hosted zone when dns_zone_id is empty."
  type        = string
  default     = ""
}

variable "dns_zone_id" {
  description = "Optional DNS zone ID. Route53 hosted zone ID or Cloudflare zone ID, depending on dns_provider."
  type        = string
  default     = ""
}

variable "cloudflare_dns_proxied" {
  description = "Whether Cloudflare should proxy the OpenVPN DNS record. OpenVPN should normally leave this false."
  type        = bool
  default     = false
}

variable "enable_vpn_access_control" {
  description = "Enable per-user OpenVPN access control managed through SSM."
  type        = bool
  default     = false
}

variable "vpn_profile_management_mode" {
  description = "authoritative manages revocation and firewall ACLs; additive only creates missing profiles and preserves existing certificates, CCD files, profiles, and firewall rules."
  type        = string
  default     = "authoritative"

  validation {
    condition     = contains(["authoritative", "additive"], var.vpn_profile_management_mode)
    error_message = "vpn_profile_management_mode must be authoritative or additive."
  }
}

variable "vpn_client_cidr" {
  description = "CIDR used by OpenVPN clients when access control is enabled."
  type        = string
  default     = "192.168.255.0/24"
}

variable "vpn_runtime_config" {
  description = "Opt-in SSM server configuration. Null preserves existing behavior. A changed pool or receive buffer restarts the OpenVPN container and disconnects clients. Requires additive profile mode or disabled profile management."
  type = object({
    dynamic_pool = optional(object({
      start = string
      end   = string
    }))
    receive_buffer_bytes = optional(number)
  })
  default = null

  validation {
    condition     = var.vpn_runtime_config == null ? true : (var.vpn_runtime_config.dynamic_pool != null || var.vpn_runtime_config.receive_buffer_bytes != null)
    error_message = "vpn_runtime_config must configure a dynamic_pool and/or receive_buffer_bytes, or be null."
  }

  validation {
    condition = try(var.vpn_runtime_config.dynamic_pool, null) == null ? true : alltrue([
      can(cidrnetmask("${var.vpn_runtime_config.dynamic_pool.start}/32")),
      can(cidrnetmask("${var.vpn_runtime_config.dynamic_pool.end}/32")),
    ])
    error_message = "The dynamic pool endpoints must be IPv4 addresses."
  }

  validation {
    condition = try(var.vpn_runtime_config.receive_buffer_bytes, null) == null ? true : try(
      var.vpn_runtime_config.receive_buffer_bytes >= 1 &&
      var.vpn_runtime_config.receive_buffer_bytes <= 2147483647 &&
      floor(var.vpn_runtime_config.receive_buffer_bytes) == var.vpn_runtime_config.receive_buffer_bytes,
    false)
    error_message = "receive_buffer_bytes must be a positive integer no larger than 2147483647."
  }
}

variable "vpn_access_groups" {
  description = "Access groups mapped to destination CIDRs allowed through the VPN."
  type = map(object({
    allowed_cidrs = list(string)
  }))
  default = {}
}

variable "vpn_users" {
  description = "OpenVPN client common names mapped to groups and optional fixed IPs. Omit ip only in additive mode to preserve dynamic allocation. Authoritative mode revokes users absent from this map."
  type = map(object({
    group = string
    ip    = optional(string)
  }))
  default = {}

  validation {
    condition     = length(distinct(compact([for user in values(var.vpn_users) : user.ip]))) == length(compact([for user in values(var.vpn_users) : user.ip]))
    error_message = "Each vpn_users entry must use a unique fixed IP."
  }

  validation {
    condition     = alltrue([for username in keys(var.vpn_users) : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", username))])
    error_message = "VPN client names may contain only letters, numbers, dots, underscores and hyphens, and must start with a letter or number."
  }

  validation {
    condition     = alltrue([for user in values(var.vpn_users) : user.ip == null ? true : can(cidrnetmask("${user.ip}/32"))])
    error_message = "Fixed VPN IPs must be valid IPv4 addresses."
  }
}
