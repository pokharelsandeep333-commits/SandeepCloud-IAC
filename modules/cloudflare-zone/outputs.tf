output "record_ids" {
  description = "Cloudflare record ID for each key in var.records and var.origin_records."
  value = merge(
    { for k, r in cloudflare_dns_record.this : k => r.id },
    { for k, r in cloudflare_dns_record.origin : k => r.id },
  )
}
