# Ad-Blocker: the public DNS-over-HTTPS server. 80/443 open to everyone by
# design; SSH only over Tailscale. The AdGuard dashboard's home-IP lock lives
# in nginx on the server, not in AWS.

module "adblocker" {
  source = "../../modules/web-host"
  count  = var.enable_adblocker ? 1 : 0

  name             = "adblocker"
  instance_name    = "Ad-Blocker-Server"
  ami              = "ami-0b6d9d3d33ba97d99"
  instance_type    = "t3.micro"
  cpu_credits      = "standard"
  root_volume_size = 25
  root_volume_name = "adblocker-root"
  backup_tag       = "sandeepcloud-daily"
  subnet_id        = data.aws_subnet.default_c.id
  vpc_id           = data.aws_vpc.default.id

  key_name   = "Ad Key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqQFJF6+TKcIfdsZbeJVUZWloEnRPnlIAB5DhtkcQeGtIGWeBLE3KLMmiEyqmMu83IhQzjwSGGyfdPTtMbwi0DXD2XSt19+n6iSWWdbZtPNV1i/K5pa/UdF5C9tUsgHbB5a4CRsRG6wbgGx3QP/48+lqaGFu4ExvqddU3zyGyhmN8rNmf4IDsRzXiNl860gQDJ/GNSlasC2U1ALz6J5uXyOJEePxmmbVKZms6zGHQCGSTLe5gV8ys1RntDYqP94uiBrS5h3LV8E0Ls8X2yVIt7AsWwCz637cNI+6hBq4sWxurxQM6TjEDHrgLPp3zAbcnYgkL5LfXdstGrl+mm3YA7 Ad Key"

  # Renaming this to adblocker-sg forces a new group, so it's a planned change, not part of the import.
  security_group_name        = "launch-wizard-3"
  security_group_description = "launch-wizard-3 created 2026-07-29T17:40:24.932Z"
  ingress_rules = {
    http  = { port = 80, cidr = "0.0.0.0/0", description = "HTTP to HTTPS redirect and Lets Encrypt HTTP-01" }
    https = { port = 443, cidr = "0.0.0.0/0", description = "Public DNS-over-HTTPS" }
  }

  status_alarms = true
}

# The resources were flat in this folder until the module refactor (2026-10-24).
# These blocks move them in state, so nothing is destroyed or recreated.

moved {
  from = aws_instance.adblocker
  to   = module.adblocker[0].aws_instance.this
}

moved {
  from = aws_eip.adblocker
  to   = module.adblocker[0].aws_eip.this
}

moved {
  from = aws_eip_association.adblocker
  to   = module.adblocker[0].aws_eip_association.this
}

moved {
  from = aws_key_pair.adblocker
  to   = module.adblocker[0].aws_key_pair.this
}

moved {
  from = aws_security_group.adblocker
  to   = module.adblocker[0].aws_security_group.this
}

moved {
  from = aws_vpc_security_group_ingress_rule.adblocker_http
  to   = module.adblocker[0].aws_vpc_security_group_ingress_rule.this["http"]
}

moved {
  from = aws_vpc_security_group_ingress_rule.adblocker_https
  to   = module.adblocker[0].aws_vpc_security_group_ingress_rule.this["https"]
}

moved {
  from = aws_vpc_security_group_egress_rule.adblocker_all
  to   = module.adblocker[0].aws_vpc_security_group_egress_rule.all
}

moved {
  from = aws_cloudwatch_metric_alarm.adblocker_status_instance
  to   = module.adblocker[0].aws_cloudwatch_metric_alarm.status_instance[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.adblocker_status_system
  to   = module.adblocker[0].aws_cloudwatch_metric_alarm.status_system[0]
}
