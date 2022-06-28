data "template_file" "user_data" {
  template = "${file("resources/templates/user_data.tpl")}"
  vars = {
    aws_region              = var.aws_region
    eip_address             = aws_eip.this.public_ip
    eip_allocation_id       = aws_eip.this.id
    s3_bucket               = aws_s3_bucket.this.name
    routes                  = var.routes
  }
}

data "template_file" "docker_compose" {
  template = file("resources/templates/user_data.tpl")
  vars     = {
    aws_region        = var.aws_region
    eip_address       = aws_eip.this.public_ip
    eip_allocation_id = aws_eip.this.id
    s3_bucket         = aws_s3_bucket.this.name
    docker_cidr       = var.docker_cidr
    routes            = var.routes
  }
}