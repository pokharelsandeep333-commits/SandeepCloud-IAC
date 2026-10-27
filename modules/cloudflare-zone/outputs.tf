output "record_ids" {
  description = "Cloudflare record ID for each key in var.records."
  value       = { for k, r in cloudflare_dns_record.this : k => r.id }
}
