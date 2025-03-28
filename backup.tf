resource "aws_backup_vault" "this" {
  name = "${var.stack_name}"
  tags = local.tags
}

resource "aws_backup_plan" "this" {
  name = "${var.stack_name}"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.backup_schedule 
    lifecycle {
      delete_after    = var.backup_retention 
    }
  }
}

data "aws_instances" "openvpn_instance" {
  filter {
    name   = "tag:Name"
    values = [var.stack_name]  
  }
}

resource "aws_backup_selection" "this" {
  name         = "${var.stack_name}"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.this.id

  resources = ["*"]  

  condition {
    string_equals {
      key   = "aws:ResourceTag/backup_enabled"
      value = "true"
    }
  }

  depends_on   = [aws_backup_plan.this, aws_iam_role.backup]
}

resource "aws_iam_role" "backup" {
  name = "${var.stack_name}-backup-role"

  assume_role_policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "backup.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  depends_on = [ aws_iam_role.backup ]
}