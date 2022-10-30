### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Get current region

data "aws_region" "aws-stacks-region" {
}

### Network resources

resource "aws_vpc" "aws-stacks-vpc" {
  cidr_block           = "192.168.42.0/24"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"

  tags = {
    Name = "aws-stacks-vpc"
  }
}

resource "aws_subnet" "aws-stacks-subnet-public-1" {
  vpc_id                  = aws_vpc.aws-stacks-vpc.id
  cidr_block              = "192.168.42.0/26"
  availability_zone       = "${data.aws_region.aws-stacks-region.name}a"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "aws-stacks-subnet-public-1"
  }
}

resource "aws_subnet" "aws-stacks-subnet-public-2" {
  vpc_id                  = aws_vpc.aws-stacks-vpc.id
  cidr_block              = "192.168.42.64/26"
  availability_zone       = "${data.aws_region.aws-stacks-region.name}b"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "aws-stacks-subnet-public-2"
  }
}

resource "aws_subnet" "aws-stacks-subnet-public-3" {
  vpc_id                  = aws_vpc.aws-stacks-vpc.id
  cidr_block              = "192.168.42.128/26"
  availability_zone       = "${data.aws_region.aws-stacks-region.name}c"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "aws-stacks-subnet-public-3"
  }
}

resource "aws_internet_gateway" "aws-stacks-igw" {
  vpc_id = aws_vpc.aws-stacks-vpc.id

  tags = {
    Name = "aws-stacks-igw"
  }
}

resource "aws_route_table" "aws-stacks-rtb-public" {
  vpc_id = aws_vpc.aws-stacks-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aws-stacks-igw.id
  }

  tags = {
    Name = "aws-stacks-rtb-public"
  }
}

resource "aws_route_table_association" "aws-stacks-rtb-association-1" {
  subnet_id      = aws_subnet.aws-stacks-subnet-public-1.id
  route_table_id = aws_route_table.aws-stacks-rtb-public.id
}

resource "aws_route_table_association" "aws-stacks-rtb-association-2" {
  subnet_id      = aws_subnet.aws-stacks-subnet-public-2.id
  route_table_id = aws_route_table.aws-stacks-rtb-public.id
}

resource "aws_route_table_association" "aws-stacks-rtb-association-3" {
  subnet_id      = aws_subnet.aws-stacks-subnet-public-3.id
  route_table_id = aws_route_table.aws-stacks-rtb-public.id
}
