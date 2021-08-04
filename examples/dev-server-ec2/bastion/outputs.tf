output "ip" {
  value = aws_instance.bastion.public_ip
}

output "keypair_name" {
  value = aws_key_pair.pubkey.key_name
}

output "security_group_id" {
  value = aws_security_group.bastion.id
}
