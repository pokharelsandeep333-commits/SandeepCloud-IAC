# Ad-Blocker: the public DNS-over-HTTPS server. 80/443 open to everyone by
# design; SSH only over Tailscale. The AdGuard dashboard's home-IP lock lives
# in nginx on the server, not in AWS.

resource "aws_instance" "adblocker" {
  ami                     = "ami-0b6d9d3d33ba97d99"
  instance_type           = "t3.micro"
  subnet_id               = data.aws_subnet.default_c.id
  vpc_security_group_ids  = [aws_security_group.adblocker.id]
  key_name                = aws_key_pair.adblocker.key_name
  disable_api_termination = true
  ebs_optimized           = true
  monitoring              = false

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 25
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name   = "adblocker-root"
      Backup = "sandeepcloud-daily"
    }
  }

  tags = {
    Name = "Ad-Blocker-Server"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami, user_data]
  }
}

resource "aws_eip" "adblocker" {
  domain = "vpc"
}

resource "aws_eip_association" "adblocker" {
  allocation_id = aws_eip.adblocker.id
  instance_id   = aws_instance.adblocker.id
}

resource "aws_key_pair" "adblocker" {
  key_name   = "Ad Key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqQFJF6+TKcIfdsZbeJVUZWloEnRPnlIAB5DhtkcQeGtIGWeBLE3KLMmiEyqmMu83IhQzjwSGGyfdPTtMbwi0DXD2XSt19+n6iSWWdbZtPNV1i/K5pa/UdF5C9tUsgHbB5a4CRsRG6wbgGx3QP/48+lqaGFu4ExvqddU3zyGyhmN8rNmf4IDsRzXiNl860gQDJ/GNSlasC2U1ALz6J5uXyOJEePxmmbVKZms6zGHQCGSTLe5gV8ys1RntDYqP94uiBrS5h3LV8E0Ls8X2yVIt7AsWwCz637cNI+6hBq4sWxurxQM6TjEDHrgLPp3zAbcnYgkL5LfXdstGrl+mm3YA7 Ad Key"

  # Same reason as aws_key_pair.sandeepcloud.
  lifecycle {
    ignore_changes = [public_key]
  }
}

# Renaming this to adblocker-sg forces a new group, so it's a planned change, not part of the import.
resource "aws_security_group" "adblocker" {
  name        = "launch-wizard-3"
  description = "launch-wizard-3 created 2026-07-29T17:40:24.932Z"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "adblocker_http" {
  security_group_id = aws_security_group.adblocker.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "adblocker_https" {
  security_group_id = aws_security_group.adblocker.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "adblocker_all" {
  security_group_id = aws_security_group.adblocker.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Status-check alarms that reboot or recover the instance on their own.
resource "aws_cloudwatch_metric_alarm" "adblocker_status_instance" {
  alarm_name          = "adblocker-status-instance"
  alarm_description   = "Ad-Blocker-Server - reboot instance on instance status check failure"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = ["arn:aws:automate:${var.region}:ec2:reboot"]

  dimensions = {
    InstanceId = aws_instance.adblocker.id
  }
}

resource "aws_cloudwatch_metric_alarm" "adblocker_status_system" {
  alarm_name          = "adblocker-status-system"
  alarm_description   = "Ad-Blocker-Server - recover instance on AWS system status check failure"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = ["arn:aws:automate:${var.region}:ec2:recover"]

  dimensions = {
    InstanceId = aws_instance.adblocker.id
  }
}
