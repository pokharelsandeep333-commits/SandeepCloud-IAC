# A Cloudflare Tunnel for SandeepCloud, created only when sandeepcloud_origin is
# tunnel: for a host with no public IP (the homelab VM). cloudflared on that host
# connects out to Cloudflare, and visitors come back in through that connection, so the
# host needs no open ports.
#
# The tunnel's token is a secret and stays out of Terraform and its state: no
# tunnel_secret here (Cloudflare generates one), and no token data source. Sandeep
# copies the token from the dashboard and installs cloudflared with it by hand, like the
# other keys (README.md).

resource "cloudflare_zero_trust_tunnel_cloudflared" "sandeepcloud" {
  count = var.sandeepcloud_origin == "tunnel" ? 1 : 0

  account_id = var.account_id
  name       = var.tunnel_name
  # Remotely managed: the routes below live in Cloudflare, not in a config file on the host
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "sandeepcloud" {
  count = var.sandeepcloud_origin == "tunnel" ? 1 : 0

  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.sandeepcloud[0].id

  config = {
    ingress = concat(
      [
        for host in concat(values(local.sandeepcloud_hosts), ["www.${local.zone}"]) : {
          hostname = host
          # cloudflared runs on the same host as nginx, which keeps serving the
          # Cloudflare origin certificate on 443. cloudflared trusts the Origin CA by
          # default, so TLS verification stays on; matching SNI to the Host header lets
          # it check the certificate against the real hostname instead of localhost.
          service = "https://localhost:443"
          origin_request = {
            match_sn_ito_host = true
          }
        }
      ],
      # Required last rule: anything else gets a 404
      [{ service = "http_status:404" }],
    )
  }
}
