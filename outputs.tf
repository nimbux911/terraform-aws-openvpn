output "autoscaling_group_id" {
  value       = aws_autoscaling_group.this.id
}
output "data_volume_id" {
  value       = aws_ebs_volume.this.id
}
output "eip_public_ip" {
  value       = aws_eip.this.public_ip
}
output "iam_role_arn" {
  value       = aws_iam_role.this.arn
}
output "security_group_id" {
  value       = aws_security_group.this.id
}
