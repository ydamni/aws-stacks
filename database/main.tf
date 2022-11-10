### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "database/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Get VPC & Subnets

data "aws_vpc" "aws-stacks-vpc" {
  filter {
    name   = "tag:Name"
    values = ["aws-stacks-vpc"]
  }
}

data "aws_subnets" "aws-stacks-subnets" {
  filter {
    name = "tag:Name"
    values = [
      "aws-stacks-subnet-public-1",
      "aws-stacks-subnet-public-2",
      "aws-stacks-subnet-public-3"
    ]
  }
}

### Security Groups

data "aws_security_group" "aws-stacks-sg-ec2" {
  filter {
    name = "tag:Name"
    values = [
      "aws-stacks-sg-ec2"
    ]
  }
}

resource "aws_security_group" "aws-stacks-sg-rds" {
  name        = "aws-stacks-sg-rds"
  description = "Only EC2 instances can access RDS DB"
  vpc_id      = data.aws_vpc.aws-stacks-vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    security_groups = [
      data.aws_security_group.aws-stacks-sg-ec2.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "aws-stacks-sg-rds"
  }
}

### RDS resources

resource "aws_db_subnet_group" "aws-stacks-rds-db-subnet-group" {
  name       = "aws-stacks-rds-db-subnet-group"
  subnet_ids = [data.aws_subnets.aws-stacks-subnets.ids[0], data.aws_subnets.aws-stacks-subnets.ids[1], data.aws_subnets.aws-stacks-subnets.ids[2]]

  tags = {
    Name = "aws-stacks-rds-db-subnet-group"
  }
}

resource "aws_db_instance" "aws-stacks-rds-db-instance" {
  identifier                 = "aws-stacks-rds-db-instance"
  engine                     = "mysql"
  engine_version             = "8.0.28"
  instance_class             = "db.t3.micro"
  multi_az                   = true
  allocated_storage          = 5
  storage_type               = "standard"
  storage_encrypted          = false
  username                   = var.db_admin_username
  password                   = var.db_admin_password
  db_name                    = "computer_store"
  parameter_group_name       = "default.mysql8.0"
  skip_final_snapshot        = true
  auto_minor_version_upgrade = false
  db_subnet_group_name       = aws_db_subnet_group.aws-stacks-rds-db-subnet-group.name
  vpc_security_group_ids     = [aws_security_group.aws-stacks-sg-rds.id]
}
