################################################################################
# IGW Edge Route Table — directs return traffic to NFW per AZ
################################################################################

resource "aws_route_table" "igw_edge" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw-edge-rt"
  }
}

resource "aws_route" "igw_to_nfw" {
  count = length(var.availability_zones)

  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = var.public_subnet_cidrs[count.index]
  vpc_endpoint_id        = local.firewall_endpoint_ids[var.availability_zones[count.index]]
}

resource "aws_route_table_association" "igw_edge" {
  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw_edge.id
}

################################################################################
# Firewall Subnet Route Tables — default route to IGW + return to NAT GW
################################################################################

resource "aws_route_table" "firewall" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-firewall-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route" "firewall_to_igw" {
  count = length(var.availability_zones)

  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "firewall" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.firewall[count.index].id
  route_table_id = aws_route_table.firewall[count.index].id
}

################################################################################
# Public Subnet Route Tables — default route through NFW endpoint
################################################################################

resource "aws_route_table" "public" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route" "public_to_nfw" {
  count = length(var.availability_zones)

  route_table_id         = aws_route_table.public[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_ids[var.availability_zones[count.index]]
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[count.index].id
}

################################################################################
# Private Subnet Route Tables — default route through NFW endpoint
################################################################################

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route" "private_to_natgw" {
  count = length(var.availability_zones)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
