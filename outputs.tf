output "endpoint_service_name" {
  description = "PrivateLink Endpoint Service name (share with RDI)"
  value       = aws_vpc_endpoint_service.svc.service_name
}

output "db_credentials_secret_arn" {
  description = "ARN of the DB credentials secret (username/password)"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "database_name" {
  description = "RDS database name"
  value       = var.db_name
}

# Handy for validating the target we attached to the TG
output "resolved_rds_private_ip" {
  description = "RDS endpoint private IP resolved at apply time"
  value       = data.external.rds_ip.result.ip
}

# NEW: connect from bastion via this host on port 5432
output "nlb_dns_name" {
  description = "Internal NLB DNS name (use this host from bastion/VPCE for psql)"
  value       = aws_lb.nlb.dns_name
}