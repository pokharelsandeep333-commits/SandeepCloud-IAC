output "tunnel_id" {
  description = "SandeepCloud's tunnel ID when sandeepcloud_origin is tunnel, for finding it in the dashboard. Not a secret: the token is what runs the tunnel."
  value       = one(cloudflare_zero_trust_tunnel_cloudflared.sandeepcloud[*].id)
}
