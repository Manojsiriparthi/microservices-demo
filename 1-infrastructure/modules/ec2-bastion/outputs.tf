output "bastion_instance_id" {
  description = "Bastion instance ID — use with: aws ssm start-session --target <id>"
  value       = aws_instance.bastion.id
}

output "bastion_security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}
