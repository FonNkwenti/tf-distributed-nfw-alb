################################################################################
# CloudWatch Log Groups for Network Firewall
################################################################################

resource "aws_cloudwatch_log_group" "nfw_alert" {
  name              = "/aws/network-firewall/${var.project_name}/alert"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-nfw-alert-logs"
  }
}

resource "aws_cloudwatch_log_group" "nfw_flow" {
  name              = "/aws/network-firewall/${var.project_name}/flow"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-nfw-flow-logs"
  }
}

################################################################################
# Network Firewall Logging Configuration
################################################################################

resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {
    log_destination_config {
      log_type             = "ALERT"
      log_destination_type = "CloudWatchLogs"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.nfw_alert.name
      }
    }

    log_destination_config {
      log_type             = "FLOW"
      log_destination_type = "CloudWatchLogs"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.nfw_flow.name
      }
    }
  }
}

################################################################################
# VPC Flow Logs
################################################################################

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/aws/vpc-flow-logs/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "${var.project_name}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-vpc-flow-log-role"
  }
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "${var.project_name}-vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination          = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type     = "cloud-watch-logs"
  iam_role_arn             = aws_iam_role.vpc_flow_log.arn
  max_aggregation_interval = 60

  tags = {
    Name = "${var.project_name}-vpc-flow-log"
  }
}
