################################################################################
# VPC
################################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

################################################################################
# Public Subnets — ALB
################################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
  }
}

################################################################################
# Firewall Subnets — AWS Network Firewall endpoints
################################################################################

resource "aws_subnet" "firewall" {
  count = length(var.firewall_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.firewall_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-firewall-${var.availability_zones[count.index]}"
  }
}

################################################################################
# Private Subnets — Web Servers
################################################################################

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
  }
}

################################################################################
# Elastic IPs for Regional NAT Gateway
################################################################################

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${var.availability_zones[count.index]}"
  }
}

################################################################################
# Regional NAT Gateway — single gateway serving all AZs
################################################################################

resource "aws_nat_gateway" "main" {
  connectivity_type = "public"
  availability_mode = "regional"

  dynamic "availability_zone_address" {
    for_each = range(length(var.availability_zones))
    content {
      allocation_ids    = [aws_eip.nat[availability_zone_address.value].id]
      availability_zone = var.availability_zones[availability_zone_address.value]
    }
  }

  tags = {
    Name = "${var.project_name}-natgw-regional"
  }

  depends_on = [aws_internet_gateway.main]
}

