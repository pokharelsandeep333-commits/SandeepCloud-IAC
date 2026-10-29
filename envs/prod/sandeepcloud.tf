# SandeepCloud: the Nextcloud/apps server. Web traffic only through Cloudflare;
# SSH only over Tailscale (no port 22 rule).

locals {
  # Cloudflare's published IPv4 ranges, as set on the security group today.
  # Phase 3 replaces this list with the cloudflare_ip_ranges data source.
  cloudflare_ipv4 = [
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "108.162.192.0/18",
    "131.0.72.0/22",
    "141.101.64.0/18",
    "162.158.0.0/15",
    "172.64.0.0/13",
    "173.245.48.0/20",
    "188.114.96.0/20",
    "190.93.240.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
  ]

  web_ports = { http = 80, https = 443 }

  # "https-104.16.0.0/13" => { port = 443, cidr = "104.16.0.0/13", description = "..." }
  sandeepcloud_ingress = {
    for pair in setproduct(keys(local.web_ports), local.cloudflare_ipv4) :
    "${pair[0]}-${pair[1]}" => {
      port        = local.web_ports[pair[0]]
      cidr        = pair[1]
      description = "Cloudflare proxy - port ${local.web_ports[pair[0]]}"
    }
  }
}

module "sandeepcloud" {
  source = "../../modules/web-host"
  count  = var.enable_sandeepcloud ? 1 : 0

  name             = "sandeepcloud"
  instance_name    = "sandeepcloud-server"
  ami              = "ami-0f8a61b66d1accaee"
  instance_type    = "t3.small"
  cpu_credits      = "unlimited"
  root_volume_size = 30
  root_volume_name = "sandeepcloud-server-root-encrypted"
  backup_tag       = "sandeepcloud-daily"
  subnet_id        = data.aws_subnet.default_c.id
  vpc_id           = data.aws_vpc.default.id

  key_name   = "sandeepcloud-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8zbL4ksv2aup9nsENVd3E1eIozZoJwDHKxZfcEEt04yPQdcDUaVrlQsiI8rcxWTX4N2EYgmSYD7UupwhSZFzEGhbG3rlLT//0a/3DG4/ZYbS3XpngPDPP97lVFF1th5HRrIFW+LASW14Jh1HiJWHVCReaMYs5MILHE6QXNzApJ5j/zHiSBtOxOqR7cGHtpSX5FvphJ9WldVDBAWcBysLeZ+dEDzGYs4jzJxGTEuVdIECb6G6xH5MsCJIMtUHOEnzqWCZsFDcMXzVS03zKvQX3OYoQTzwmZroikO3dRW/xQtZ28Zo8B7pXMJptge7Z4NHcsBDQQPC7unFb31zVDM6X sandeepcloud-key"

  security_group_name        = "sandeepcloud-sg"
  security_group_description = "sandeepcloud-sg created 2026-06-27T21:49:11.753Z"
  ingress_rules              = local.sandeepcloud_ingress

  # The Ad-Blocker has these and SandeepCloud doesn't yet. Adding them is its own change.
  status_alarms = false

  # TEARDOWN (2026-10-28): apply this first (in place), then set the enable_ switch to false.
  termination_protection = false
}

# The resources were flat in this folder until the module refactor (2026-10-24).
# These blocks move them in state, so nothing is destroyed or recreated.

moved {
  from = aws_instance.sandeepcloud
  to   = module.sandeepcloud[0].aws_instance.this
}

moved {
  from = aws_eip.sandeepcloud
  to   = module.sandeepcloud[0].aws_eip.this
}

moved {
  from = aws_eip_association.sandeepcloud
  to   = module.sandeepcloud[0].aws_eip_association.this
}

moved {
  from = aws_key_pair.sandeepcloud
  to   = module.sandeepcloud[0].aws_key_pair.this
}

moved {
  from = aws_security_group.sandeepcloud
  to   = module.sandeepcloud[0].aws_security_group.this
}

# All 30 Cloudflare rules move together; their keys don't change.
moved {
  from = aws_vpc_security_group_ingress_rule.sandeepcloud_cloudflare
  to   = module.sandeepcloud[0].aws_vpc_security_group_ingress_rule.this
}

moved {
  from = aws_vpc_security_group_egress_rule.sandeepcloud_all
  to   = module.sandeepcloud[0].aws_vpc_security_group_egress_rule.all
}
