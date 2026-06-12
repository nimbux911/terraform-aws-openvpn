locals {
  dns_zone_id = var.dns_zone_id != "" ? var.dns_zone_id : (
    var.dns_provider == "route53" ? try(data.aws_route53_zone.dns[0].zone_id, "") : try(data.cloudflare_zone.dns[0].zone_id, "")
  )
}

resource "aws_route53_record" "openvpn" {
  count = var.dns_name != "" && var.dns_provider == "route53" ? 1 : 0

  zone_id = local.dns_zone_id
  name    = var.dns_name
  type    = "A"
  ttl     = 60
  records = [aws_eip.this.public_ip]
}

resource "cloudflare_dns_record" "openvpn" {
  count = var.dns_name != "" && var.dns_provider == "cloudflare" ? 1 : 0

  zone_id = local.dns_zone_id
  name    = var.dns_name
  content = aws_eip.this.public_ip
  type    = "A"
  ttl     = 60
  proxied = var.cloudflare_dns_proxied
}
