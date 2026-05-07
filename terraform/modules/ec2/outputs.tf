output "bastion_public_ip"       { value = aws_instance.bastion.public_ip }
output "bastion_instance_id"     { value = aws_instance.bastion.id }
output "web_server_ids"          { value = aws_instance.web[*].id }
output "web_server_private_ips"  { value = aws_instance.web[*].private_ip }
output "bastion_key_secret_arn"  { value = aws_secretsmanager_secret.bastion_key.arn }
output "web_key_secret_arns"     { value = aws_secretsmanager_secret.web_key[*].arn }
