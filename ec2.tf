################################################################################
# Latest Amazon Linux 2023 AMI
################################################################################

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

################################################################################
# IAM Role for SSM access
################################################################################

resource "aws_iam_role" "web_server" {
  name = "${var.project_name}-web-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-web-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.web_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web_server" {
  name = "${var.project_name}-web-profile"
  role = aws_iam_role.web_server.name
}

################################################################################
# Web Server Security Group
################################################################################

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

################################################################################
# EC2 Web Servers — one per AZ in private subnets
################################################################################

resource "aws_instance" "web" {
  count = length(var.availability_zones)

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web_server.name

  user_data_base64 = base64encode(<<-USERDATA
    #!/bin/bash
    dnf update -y
    dnf install -y httpd
    systemctl start httpd
    systemctl enable httpd
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    cat <<HTML > /var/www/html/index.html
    <!DOCTYPE html>
    <html>
    <head><title>NFW Demo</title></head>
    <body style="font-family:Arial,sans-serif;text-align:center;padding:50px;">
      <h1>🔥 AWS Network Firewall — Distributed Architecture</h1>
      <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
      <p><strong>Availability Zone:</strong> $AZ</p>
      <p>Traffic to this page was inspected by AWS Network Firewall.</p>
    </body>
    </html>
    HTML
  USERDATA
  )

  tags = {
    Name = "${var.project_name}-web-${var.availability_zones[count.index]}"
  }

  depends_on = [
    aws_nat_gateway.main,
    aws_route.private_to_natgw
  ]
}

################################################################################
# Register instances with ALB target group
################################################################################

resource "aws_lb_target_group_attachment" "web" {
  count = length(var.availability_zones)

  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}
