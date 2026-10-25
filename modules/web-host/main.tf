# One public web server: instance, Elastic IP, key pair, security group and its
# rules, and optional status-check alarms. Used once per server by envs/prod.
# SSH goes over Tailscale, so no rule here ever opens port 22.

data "aws_region" "current" {}

# These skips cover every server this module builds (SandeepCloud and the Ad-Blocker today).
resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_126:Detailed monitoring is about $2.10/instance/month; the status-check alarms already get free 1-minute metrics
  #checkov:skip=CKV2_AWS_41:Neither server calls AWS APIs; no instance role means no AWS credentials on the box to steal via IMDS. Revisit if they ever read SSM parameters
  ami                     = var.ami
  instance_type           = var.instance_type
  subnet_id               = var.subnet_id
  vpc_security_group_ids  = [aws_security_group.this.id]
  key_name                = aws_key_pair.this.key_name
  disable_api_termination = true
  ebs_optimized           = true
  monitoring              = false

  credit_specification {
    cpu_credits = var.cpu_credits
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name   = var.root_volume_name
      Backup = var.backup_tag
    }
  }

  tags = {
    Name = var.instance_name
  }

  # Lifecycle can't take variables, so this protects every server the module
  # builds. Turning off a server that's in state therefore fails the plan.
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami, user_data]
  }
}

resource "aws_eip" "this" {
  domain = "vpc"
}

resource "aws_eip_association" "this" {
  allocation_id = aws_eip.this.id
  instance_id   = aws_instance.this.id
}

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = var.public_key

  # AWS doesn't hand the public key back on import, and public_key forces
  # replacement, so without this the first plan would recreate the key pair.
  lifecycle {
    ignore_changes = [public_key]
  }
}

resource "aws_security_group" "this" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  #checkov:skip=CKV_AWS_260:Ad-Blocker only (SandeepCloud allows Cloudflare ranges only): port 80 is open to all for the HTTP-to-HTTPS redirect and Let's Encrypt HTTP-01 renewal
  for_each = var.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# Both servers need outbound traffic: OS updates, Docker pulls, Tailscale, Let's
# Encrypt and (Ad-Blocker) upstream DNS. Port-restricted egress gets tried in the
# fire drill, where a wrong rule can't break a live server.
#trivy:ignore:AVD-AWS-0104 Open egress kept for now, see the comment above
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound: updates, Docker pulls, Tailscale, Lets Encrypt, upstream DNS"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Status-check alarms that reboot or recover the instance on their own.
resource "aws_cloudwatch_metric_alarm" "status_instance" {
  count = var.status_alarms ? 1 : 0

  alarm_name          = "${var.name}-status-instance"
  alarm_description   = "${var.instance_name} - reboot instance on instance status check failure"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.region}:ec2:reboot"]

  dimensions = {
    InstanceId = aws_instance.this.id
  }
}

resource "aws_cloudwatch_metric_alarm" "status_system" {
  count = var.status_alarms ? 1 : 0

  alarm_name          = "${var.name}-status-system"
  alarm_description   = "${var.instance_name} - recover instance on AWS system status check failure"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.region}:ec2:recover"]

  dimensions = {
    InstanceId = aws_instance.this.id
  }
}
