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