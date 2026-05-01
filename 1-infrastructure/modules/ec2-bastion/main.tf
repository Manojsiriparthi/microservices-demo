# ============================================================================
# EC2 BASTION — SSM SESSION MANAGER ACCESS ONLY
# ============================================================================
#
# Access method: AWS Systems Manager Session Manager
#   - No SSH key required
#   - No port 22 open
#   - No public IP needed
#   - Session established via SSM agent → AWS SSM endpoint (HTTPS 443)
#   - Full session audit trail in CloudWatch / S3
#
# Connect:
#   aws ssm start-session --target <instance-id> --region us-east-1
#
# Security Group:
#   - No inbound rules — SSM does not require any inbound port
#   - Outbound 443 only — SSM agent calls AWS endpoints over HTTPS
# ============================================================================

# Latest Amazon Linux 2023 AMI — SSM agent pre-installed
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ============================================================================
# SECURITY GROUP — no inbound, outbound 443 only
# ============================================================================

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-${var.environment}-bastion-sg"
  description = "Bastion host — SSM only, no inbound rules required"
  vpc_id      = var.vpc_id

  # No inbound rules — SSM Session Manager does not need any inbound port

  # Outbound 443 only — SSM agent communicates with AWS endpoints over HTTPS
  egress {
    description = "HTTPS to AWS SSM and EC2 endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # AWS endpoint IPs are dynamic; VPC endpoints can restrict this further
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion-sg"
  })
}

# ============================================================================
# BASTION EC2 INSTANCE
# Placed in a private subnet — no public IP needed for SSM access.
# ============================================================================

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id   # private subnet — no public IP needed
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = var.iam_instance_profile_name

  # No key_name — SSH access disabled, SSM only

  # IMDSv2 — prevents SSRF / credential-theft via metadata endpoint
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  # AL2023 has SSM agent pre-installed; ensure it is running
  user_data = <<-EOF
    #!/bin/bash
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
