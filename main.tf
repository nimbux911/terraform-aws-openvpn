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
  vpc_zone_identifier  = [var.subnet_ids[0]]
  health_check_type    = "EC2"
  tag {
    key                 = "Name"
    value               = "${var.environment}-openvpn"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "this" {
  iam_instance_profile        = aws_iam_instance_profile.this.name
  image_id                    = var.ami_id
  instance_type               = var.instance_type
  name_prefix                 = "${var.environment}-openvpn"
  security_groups             = [aws_security_group.this.id]
  key_name                    = "${var.environment}-openvpn"
  associate_public_ip_address = true
  user_data                   = templatefile("${path.module}/resources/templates/user_data.tpl", 
      {
        aws_region        = data.aws_region.current.name,
        eip_address       = aws_eip.this.public_ip,
        eip_allocation_id = aws_eip.this.id,
        s3_bucket         = aws_s3_bucket.this.bucket,
        docker_cidr       = var.docker_cidr
        routes            = [ for peered_network in var.peered_networks : "${element(split("/", peered_network), 0)} ${cidrnetmask(peered_network)}" ]
      }
    )
  lifecycle {
    create_before_destroy = true
  }
}





