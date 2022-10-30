### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "compute/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Get current region

data "aws_region" "aws-stacks-region" {
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

resource "aws_security_group" "aws-stacks-sg" {
  name        = "aws-stacks-sg"
  description = "Allow HTTP, HTTPS & SSH"
  vpc_id      = data.aws_vpc.aws-stacks-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "aws-stacks-sg"
  }
}

### SSH Key for EC2 instance

resource "tls_private_key" "aws-stacks-tls-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "aws-stacks-key-pair" {
  key_name   = "aws-stacks-ec2-access-key"
  public_key = tls_private_key.aws-stacks-tls-key.public_key_openssh
}

resource "local_file" "aws-stacks-file-key" {
  content  = tls_private_key.aws-stacks-tls-key.private_key_pem
  filename = "aws-stacks-ec2-access-key.pem"
}

### Get AMI

data "aws_ami" "aws-stacks-ami" {
  most_recent = true

  filter {
    name   = "image-id"
    values = ["ami-09d3b3274b6c5d4aa"] ### Amazon Linux 2 AMI for us-east-1
  }
}

### EC2 instances

resource "aws_instance" "aws-stacks-instance-1" {
  instance_type          = "t2.micro"
  ami                    = data.aws_ami.aws-stacks-ami.id
  subnet_id              = data.aws_subnets.aws-stacks-subnets.ids[0]
  vpc_security_group_ids = [aws_security_group.aws-stacks-sg.id]
  key_name               = aws_key_pair.aws-stacks-key-pair.key_name
  user_data              = var.user_data

  tags = {
    Name = "aws-stacks-instance-1"
  }
}

resource "aws_instance" "aws-stacks-instance-2" {
  instance_type          = "t2.micro"
  ami                    = data.aws_ami.aws-stacks-ami.id
  subnet_id              = data.aws_subnets.aws-stacks-subnets.ids[1]
  vpc_security_group_ids = [aws_security_group.aws-stacks-sg.id]
  key_name               = aws_key_pair.aws-stacks-key-pair.key_name
  user_data              = var.user_data

  tags = {
    Name = "aws-stacks-instance-2"
  }
}

resource "aws_instance" "aws-stacks-instance-3" {
  instance_type          = "t2.micro"
  ami                    = data.aws_ami.aws-stacks-ami.id
  subnet_id              = data.aws_subnets.aws-stacks-subnets.ids[2]
  vpc_security_group_ids = [aws_security_group.aws-stacks-sg.id]
  key_name               = aws_key_pair.aws-stacks-key-pair.key_name
  user_data              = var.user_data

  tags = {
    Name = "aws-stacks-instance-3"
  }
}
