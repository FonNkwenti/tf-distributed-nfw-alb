################################################################################
# AWS Network Firewall
################################################################################

resource "aws_networkfirewall_firewall" "main" {
  name                = "${var.project_name}-nfw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.main.id
  description         = "Distributed AWS Network Firewall for inspecting all ingress/egress traffic"

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall[*].id
    content {
      subnet_id = subnet_mapping.value
    }
  }

  tags = {
    Name = "${var.project_name}-nfw"
  }
}

################################################################################
# Firewall Policy
################################################################################

resource "aws_networkfirewall_firewall_policy" "main" {
  name = "${var.project_name}-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateless_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateless.arn
      priority     = 100
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful.arn
    }
  }

  tags = {
    Name = "${var.project_name}-policy"
  }
}

################################################################################
# Stateless Rule Group — Forward everything to stateful engine
################################################################################

resource "aws_networkfirewall_rule_group" "stateless" {
  name     = "${var.project_name}-stateless-rg"
  type     = "STATELESS"
  capacity = 50

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 10
          rule_definition {
            match_attributes {
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
            actions = ["aws:forward_to_sfe"]
          }
        }
      }
    }
  }

  tags = {
    Name = "${var.project_name}-stateless-rg"
  }
}

################################################################################
# Stateful Rule Group — Allow HTTP, HTTPS, and ICMP
################################################################################

resource "aws_networkfirewall_rule_group" "stateful" {
  name     = "${var.project_name}-stateful-rg"
  type     = "STATEFUL"
  capacity = 100

  rule_group {
    rules_source {
      rules_string = <<-RULES
        pass tcp any any -> any 80 (msg:"Allow HTTP"; sid:100001; rev:1;)
        pass tcp any any -> any 443 (msg:"Allow HTTPS"; sid:100002; rev:1;)
        pass icmp any any -> any any (msg:"Allow ICMP"; sid:100003; rev:1;)
        pass tcp any 80 -> any any (msg:"Allow HTTP response"; sid:100004; rev:1;)
        pass tcp any 443 -> any any (msg:"Allow HTTPS response"; sid:100005; rev:1;)
      RULES
    }
  }

  tags = {
    Name = "${var.project_name}-stateful-rg"
  }
}

################################################################################
# Local — Extract VPC endpoint IDs per AZ for routing
################################################################################

locals {
  # The firewall returns sync states keyed by AZ. We need the VPC endpoint ID
  # for each AZ to set up per-AZ routing through the firewall.
  firewall_endpoint_ids = {
    for sync_state in aws_networkfirewall_firewall.main.firewall_status[0].sync_states :
    sync_state.availability_zone => sync_state.attachment[0].endpoint_id
  }
}
