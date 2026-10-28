# Offline plan tests: all providers mocked, no real apply or AWS calls.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
  mock_data "aws_subnet" {
    defaults = { availability_zone = "us-east-1a" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-openvpn" }
  }
  mock_resource "aws_eip" {
    defaults = { public_ip = "198.51.100.1" }
  }
}
mock_provider "cloudflare" {}
mock_provider "tls" {}

variables {
  vpc_id                      = "vpc-0123456789abcdef0"
  subnet_id                   = "subnet-0123456789abcdef0"
  ubuntu_ami_id               = "ami-0123456789abcdef0"
  dns_name                    = "vpn.example.test"
  dns_zone_id                 = "Z0123456789ABCDEF"
  enable_vpn_access_control   = true
  vpn_profile_management_mode = "additive"
  vpn_access_groups           = { admins = { allowed_cidrs = [] } }
  vpn_users = {
    dynamic = { group = "admins" }
    fixed   = { group = "admins", ip = "192.168.255.11" }
  }
}

run "runtime_is_disabled_by_default" {
  command = plan
  assert {
    condition     = local.runtime_config == "" && length(yamldecode(aws_ssm_document.access_control[0].content).mainSteps) == 1
    error_message = "Existing callers must not acquire a runtime/restart step by default."
  }
}

run "explicit_runtime_runs_before_profiles_and_stops_on_failure" {
  command = plan
  variables {
    vpn_runtime_config = {
      dynamic_pool         = { start = "192.168.255.101", end = "192.168.255.200" }
      receive_buffer_bytes = 1048576
    }
  }
  assert {
    condition     = [for step in yamldecode(aws_ssm_document.access_control[0].content).mainSteps : step.name] == ["applyRuntimeConfiguration", "applyAccessControl"]
    error_message = "Runtime validation/restart must precede profile synchronization."
  }
  assert {
    condition     = yamldecode(aws_ssm_document.access_control[0].content).mainSteps[0].inputs.onFailure == "exit" && length(aws_ssm_document.access_control[0].content) < 65536
    error_message = "The document must stop on runtime failure and fit the SSM size limit."
  }
}

run "authoritative_default_remains_unchanged" {
  command = plan
  variables {
    vpn_profile_management_mode = "authoritative"
    vpn_users                   = { fixed = { group = "admins", ip = "192.168.255.11" } }
  }
  assert {
    condition     = length(yamldecode(aws_ssm_document.access_control[0].content).mainSteps) == 1 && strcontains(local.access_control, "iptables")
    error_message = "Legacy authoritative behavior must remain unchanged without runtime settings."
  }
}

run "overlapping_pool_is_rejected" {
  command = plan
  variables {
    vpn_runtime_config = { dynamic_pool = { start = "192.168.255.10", end = "192.168.255.200" } }
  }
  expect_failures = [aws_ssm_document.access_control[0]]
}

run "runtime_cannot_erase_authoritative_acls" {
  command = plan
  variables {
    vpn_profile_management_mode = "authoritative"
    vpn_users                   = { fixed = { group = "admins", ip = "192.168.255.11" } }
    vpn_runtime_config          = { receive_buffer_bytes = 1048576 }
  }
  expect_failures = [aws_ssm_document.access_control[0]]
}
