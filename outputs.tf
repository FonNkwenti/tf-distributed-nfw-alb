################################################################################
# Outputs
################################################################################

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL to access the web application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "firewall_arn" {
  description = "ARN of the AWS Network Firewall"
  value       = aws_networkfirewall_firewall.main.arn
}

output "firewall_endpoint_ids" {
  description = "Network Firewall VPC endpoint IDs per AZ"
  value       = local.firewall_endpoint_ids
}

output "web_server_instance_ids" {
  description = "EC2 instance IDs of the web servers"
  value       = aws_instance.web[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}
