resource "aws_backup_vault" "this" {
  name = "${var.stack_name}-backup-vault"
  tags = local.tags
}

resource "aws_backup_plan" "this" {
  name = "${var.stack_name}-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 5 * * ? *)" 
    lifecycle {
      delete_after = 7 
    }
  }
}

resource "aws_backup_selection" "this" {
  name          = "${var.stack_name}-backup-selection"
  iam_role_arn  = aws_iam_role.backup.arn
  plan_id       = aws_backup_plan.this.id

  resources = [aws_autoscaling_group.this.id]

  depends_on = [ aws_backup_plan.this, aws_iam_role.backup ]
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