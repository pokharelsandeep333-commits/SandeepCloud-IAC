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

  # "https-104.16.0.0/13" => { port = 443, cidr = "104.16.0.0/13" }
  sandeepcloud_ingress = {
    for pair in setproduct(keys(local.web_ports), local.cloudflare_ipv4) :
    "${pair[0]}-${pair[1]}" => { port = local.web_ports[pair[0]], cidr = pair[1] }
  }
}

resource "aws_instance" "sandeepcloud" {
  ami                     = "ami-0f8a61b66d1accaee"
  instance_type           = "t3.small"
  subnet_id               = data.aws_subnet.default_c.id
  vpc_security_group_ids  = [aws_security_group.sandeepcloud.id]
  key_name                = aws_key_pair.sandeepcloud.key_name
  disable_api_termination = true
  ebs_optimized           = true
  monitoring              = false

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name   = "sandeepcloud-server-root-encrypted"
      Backup = "sandeepcloud-daily"
    }
  }

  tags = {
    Name = "sandeepcloud-server"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami, user_data]
  }
}

resource "aws_eip" "sandeepcloud" {
  domain = "vpc"
}

resource "aws_eip_association" "sandeepcloud" {
  allocation_id = aws_eip.sandeepcloud.id
  instance_id   = aws_instance.sandeepcloud.id
}

resource "aws_key_pair" "sandeepcloud" {
  key_name   = "sandeepcloud-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8zbL4ksv2aup9nsENVd3E1eIozZoJwDHKxZfcEEt04yPQdcDUaVrlQsiI8rcxWTX4N2EYgmSYD7UupwhSZFzEGhbG3rlLT//0a/3DG4/ZYbS3XpngPDPP97lVFF1th5HRrIFW+LASW14Jh1HiJWHVCReaMYs5MILHE6QXNzApJ5j/zHiSBtOxOqR7cGHtpSX5FvphJ9WldVDBAWcBysLeZ+dEDzGYs4jzJxGTEuVdIECb6G6xH5MsCJIMtUHOEnzqWCZsFDcMXzVS03zKvQX3OYoQTzwmZroikO3dRW/xQtZ28Zo8B7pXMJptge7Z4NHcsBDQQPC7unFb31zVDM6X sandeepcloud-key"

  # AWS doesn't hand the public key back on import, and public_key forces
  # replacement, so without this the first plan would recreate the key pair.
  lifecycle {
    ignore_changes = [public_key]
  }
}

resource "aws_security_group" "sandeepcloud" {
  name        = "sandeepcloud-sg"
  description = "sandeepcloud-sg created 2026-06-27T21:49:11.753Z"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "sandeepcloud_cloudflare" {
  for_each = local.sandeepcloud_ingress

  security_group_id = aws_security_group.sandeepcloud.id
  description       = "Cloudflare proxy - port ${each.value.port}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_egress_rule" "sandeepcloud_all" {
  security_group_id = aws_security_group.sandeepcloud.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
