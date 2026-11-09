# The API token comes from the CLOUDFLARE_API_TOKEN environment variable, read from a
# file outside this repo (README.md). Scope: this zone only, DNS Write + Email Routing
# Rules Write + Zone WAF Write (security.tf); plus Account: Cloudflare Tunnel Write and
# Notifications Write, needed only when sandeepcloud_origin is tunnel.
provider "cloudflare" {}
