resource "aws_vpc" "nagaza-vpc" {
  cidr_block = local.vpc_cidr
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = local.vpc_name
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  count = local.public_subnet_size
  cidr_block = cidrsubnet(local.public_subnet_cidr_prefix, 4, count.index)

  vpc_id = aws_vpc.nagaza-vpc.id
  availability_zone = element(data.aws_availability_zones.available.names, count.index % local.az_count)

  tags = {
    Name = "${local.vpc_name}-subnet-public-${count.index + 1}"
    VpcName = local.vpc_name
  }
}

resource "aws_route_table_association" "public" {
  count = local.public_subnet_size

  route_table_id = aws_route_table.public[count.index % local.az_count].id
  subnet_id = aws_subnet.public[count.index].id
}

resource "aws_network_acl_association" "public" {
  count = local.public_subnet_size

  network_acl_id = aws_network_acl.public.id
  subnet_id = aws_subnet.public[count.index].id
}

resource "aws_route_table" "public" {
  count = local.az_count #AZ개수만큼 만들어지고, AZ 순서대로임
  vpc_id = aws_vpc.nagaza-vpc.id
  tags = {
    Name = "${local.vpc_name}-rt-public-${count.index + 1}"
  }
}

resource "aws_route" "igw_route" {
  count = local.az_count
  route_table_id = aws_route_table.public[count.index].id
  gateway_id = aws_internet_gateway.igw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.nagaza-vpc.id

  tags = {
    Name = "${local.vpc_name}-acl-public"
  }
}

resource "aws_network_acl_rule" "public_outbound_allow_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = -1
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}


resource "aws_network_acl_rule" "public_inbound_allow_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = -1
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.nagaza-vpc.id
  tags = {
    Name = "${local.vpc_name}-igw"
  }
}

resource "aws_subnet" "private" {
  count = local.private_subnet_size
  cidr_block = cidrsubnet(local.private_subnet_cidr_prefix, 4, count.index)

  vpc_id = aws_vpc.nagaza-vpc.id
  availability_zone = element(data.aws_availability_zones.available.names, count.index % local.az_count)
  # if) az_count = 2 이고, az별 subnet 수가 2이면 1a, 1b, 1a, 1b

  tags = {
    Name = "${local.vpc_name}-subnet-private-${count.index + 1}"
    VpcName = local.vpc_name
  }
}

resource "aws_route_table_association" "private" {
  count = local.private_subnet_size

  route_table_id = aws_route_table.private[count.index % local.az_count].id
  subnet_id = aws_subnet.private[count.index].id
}

resource "aws_network_acl_association" "private" {
  count = local.private_subnet_size

  network_acl_id = aws_network_acl.private.id
  subnet_id = aws_subnet.private[count.index].id
}

resource "aws_route_table" "private" {
  count = local.az_count #AZ개수만큼 만들어지고, AZ 순서대로임
  vpc_id = aws_vpc.nagaza-vpc.id
  tags = {
    Name = "${local.vpc_name}-rt-private-${count.index + 1}"
  }
}

resource "aws_route" "nat_route" {
  count = local.az_count
  route_table_id = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat[0].id
}
resource "aws_eip" "nat_eip" {
  count = 1
  domain = "vpc"

  depends_on = [aws_internet_gateway.igw] # 사실 이 VPC 모듈 구조상 없을 수 없긴 함
  tags = {
    Name = "${local.vpc_name}-eip-nat-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat" {
  count = 1
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id = aws_subnet.public[count.index].id
  # FIXME: 이거 Public Subnet이 AZ별로 순서대로 만들어진다는 내 코드상 가설떄문에 가능한 로직

  tags = {
    Name = "${local.vpc_name}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.nagaza-vpc.id

  tags = {
    Name = "${local.vpc_name}-acl-private"
  }
}

resource "aws_network_acl_rule" "private_outbound_allow_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = -1
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}


resource "aws_network_acl_rule" "private_inbound_allow_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = -1
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_vpc_endpoint" "ecr-api-endpoint" {
  vpc_id       = aws_vpc.nagaza-vpc.id
  service_name = "com.amazonaws.ap-northeast-2.ecr.api"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  security_group_ids = [aws_security_group.ecr-endpoint.id]
  subnet_ids = aws_subnet.private.*.id
}

resource "aws_vpc_endpoint" "dkr-api-endpoint" {
  vpc_id       = aws_vpc.nagaza-vpc.id
  service_name = "com.amazonaws.ap-northeast-2.ecr.dkr"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  security_group_ids = [aws_security_group.ecr-endpoint.id]
  subnet_ids = aws_subnet.private.*.id
}

resource "aws_security_group" "ecr-endpoint" {
  name        = "ecr-endpoint-sg"
  description = "Prod Ecr Endpoint Security Group"
  vpc_id      = aws_vpc.nagaza-vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    security_groups = [aws_security_group.nagaza-prod-ecs-sg.id]
    from_port       = 0
    to_port         = 0
    protocol        = "tcp"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }

  tags = {
    Name = "ecr-endpoint-sg"
  }
}


