output "security_perimeter_enabled" {
  type        = list(string)
  description = "Is the NSP (Network Servucirty Perimeter) enabled or not"
  sensitive   = false
  value       = var.security_perimeter_enabled
}

output "security_perimeter_inbound_public_ips" {
  type        = list(string)
  description = "List of public IPs allowed for inbound traffic to the security perimeter"
  sensitive   = false
  value       = var.security_perimeter_inbound_public_ips
}

output "security_perimeter_inbound_service_tags" {
  type        = list(string)
  description = "List of public IPs allowed for inbound traffic to the security perimeter"
  sensitive   = false
  value       = var.security_perimeter_inbound_service_tags
}

output "security_perimeter_outbound_fqdns" {
  type        = list(string)
  description = "List of FQDNs allowed for outbound traffic from the security perimeter"
  sensitive   = false
  value       = var.security_perimeter_outbound_fqdns
}
