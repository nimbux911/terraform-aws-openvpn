resource "aws_security_group" "this" {
  name        = "${var.environment}-openvpn"
  description = "OpenVPN"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "ingress_openvpn" {
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  description       = "OpenVPN"
  from_port         = 1194
  to_port           = 1194
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "egress_all" {
  security_group_id = aws_security_group.this.id
  type              = "egress"
  description       = "Allow all egress traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ingress_ssh" {
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  description       = "SSH"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  self              = true
}