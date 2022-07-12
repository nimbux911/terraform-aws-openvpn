resource "aws_s3_bucket" "this" {
  bucket = "${var.environment}-openvpn"
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  acl    = "private"
}

resource "aws_s3_object" "script" {
  for_each = fileset(path.module, "resources/scripts/*")
  bucket   = aws_s3_bucket.this.bucket
  key      = basename(each.value)
  source   = "${path.module}/${each.value}"
}

resource "aws_s3_object" "docker_compose" {
  bucket = aws_s3_bucket.this.bucket
  key    = "docker-compose.yml"
  content = templatefile("${path.module}/resources/templates/docker-compose.yaml.tpl", { compose_cidr = "192.168.0.1/24" })
}
