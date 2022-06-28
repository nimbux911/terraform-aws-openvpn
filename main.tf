resource "aws_key_pair" "this" {
  key_name   = "openvpn-key"
  public_key = base64decode(aws_ssm_parameter.public_key.value)
}

resource "aws_eip" "this" {
  vpc      = true
  tags = {
    Name = "${var.environment}-openvpn"
  }
}

resource "aws_autoscaling_group" "this" {
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.this.id
  max_size             = 1
  min_size             = 1
  name                 = "${var.environment}-openvpn"
  vpc_zone_identifier  = [var.subnet_id]
  health_check_type    = "EC2"
  tag {
    key                 = "Name"
    value               = "${var.environment}-openvpn"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "this" {
  iam_instance_profile        = aws_iam_instance_profile.this.name
  image_id                    = var.openvpn_ami_id
  instance_type               = var.openvpn_instance_type
  name_prefix                 = "${var.environment}-openvpn-"
  security_groups             = [aws_security_group.this.id]
  key_name                    = "${var.environment}-openvpn"
  associate_public_ip_address = true
  user_data                   = templatefile("${path.module}/resources/templates/user_data.tpl", 
      {
        aws_region        = data.aws_region.current.name,
        eip_address       = aws_eip.this.public_ip,
        eip_allocation_id = aws_eip.this.id,
        s3_bucket         = aws_s3_bucket.this.name,
        docker_cidr       = var.docker_cidr
        routes            = [ for peered_network in var.peered_networks : "${element(split("/", peered_network), 0)} ${cidrnetmask(peered_network)}" ]
      }
    )
  lifecycle {
    create_before_destroy = true
  }
}

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

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_ssm_parameter" "public_key" {
  name  = "${var.environment}-openvpn-public-ssh-key"
  type  = "SecureString"
  value = base64encode(tls_private_key.this.public_key_openssh)
}

resource "aws_ssm_parameter" "private_key" {
  name  = "${var.environment}-openvpn-private-ssh-key"
  type  = "SecureString"
  tier  = "Advanced"
  value = base64encode(tls_private_key.this.private_key_pem)
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.environment}-openvpn"
  acl    = "private"
}

resource "aws_s3_bucket_object" "script" {
  for_each = fileset(path.module, "resource/scripts/*")
  bucket   = aws_s3_bucket.this.bucket
  key      = basename(each.value)
  source   = "${path.module}/${each.value}"
}

resource "aws_s3_bucket_object" "docker_compose" {
  bucket = aws_s3_bucket.this.bucket
  key    = "docker-compose.yml"
  source = templatefile("${path.module}/resources/templates/docker-compose.yml.tpl", { docker_cidr = var.docker_cidr })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.environment}-openvpn"
  role = aws_iam_role.this.name
}

resource "aws_iam_role" "this" {
  name = "${var.environment}-openvpn"
    assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.environment}-openvpn"
  role   = aws_iam_role.this.id
  policy = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeParameters",
                "ssm:GetParameterHistory",
                "ssm:DescribeDocumentParameters",
                "ssm:GetParametersByPath",
                "ssm:GetParameters",
                "ssm:GetParameter",
                "secretsmanager:ListSecrets",
                "secretsmanager:GetSecretValue",
                "ec2:AssociateAddress",
                "ec2:DisassociateAddress",
                "secretsmanager:DescribeSecret" 
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
              "arn:aws:s3:::${aws_s3_bucket.this.bucket}",
              "arn:aws:s3:::${aws_s3_bucket.this.bucket}/*"
            ]
        }
    ]
}
  EOF
}