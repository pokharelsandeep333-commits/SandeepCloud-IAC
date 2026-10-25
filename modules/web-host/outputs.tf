output "instance_id" {
  description = "ID of the instance."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "The Elastic IP address (what DNS points at)."
  value       = aws_eip.this.public_ip
}

output "security_group_id" {
  description = "ID of the server's security group."
  value       = aws_security_group.this.id
}
