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

resource "aws_security_group" "aws-stacks-sg-lb" {
  name        = "aws-stacks-sg-lb"
  description = "Allow HTTP & HTTPS on ALB"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "aws-stacks-sg-lb"
  }
}

resource "aws_security_group" "aws-stacks-sg-ec2" {
  name        = "aws-stacks-sg-ec2"
  description = "Allow full access to EC2 from ALB only + enable SSH using generated key"
  vpc_id      = data.aws_vpc.aws-stacks-vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    security_groups = [
      aws_security_group.aws-stacks-sg-lb.id
    ]
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
    Name = "aws-stacks-sg-ec2"
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

### Launch Configuration for ASG

resource "aws_launch_configuration" "aws-stacks-launch-configuration" {
  instance_type   = "t2.micro"
  name_prefix     = "aws-stacks-asg-"
  image_id        = data.aws_ami.aws-stacks-ami.id
  security_groups = [aws_security_group.aws-stacks-sg-ec2.id]
  key_name        = aws_key_pair.aws-stacks-key-pair.key_name
  user_data       = var.user_data

  lifecycle {
    create_before_destroy = true
  }
}

### ASG

resource "aws_autoscaling_group" "aws-stacks-asg" {
  min_size             = 3
  max_size             = 6
  desired_capacity     = 3
  launch_configuration = aws_launch_configuration.aws-stacks-launch-configuration.name
  vpc_zone_identifier  = [data.aws_subnets.aws-stacks-subnets.ids[0], data.aws_subnets.aws-stacks-subnets.ids[1], data.aws_subnets.aws-stacks-subnets.ids[2]]

  lifecycle {
    ignore_changes = [desired_capacity, target_group_arns]
  }

  tag {
    key                 = "Name"
    value               = "aws-stacks-asg"
    propagate_at_launch = true
  }
}

### Target Group for ALB

resource "aws_lb_target_group" "aws-stacks-lb-target-group-http" {
  name        = "aws-stacks-tg-http"
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.aws-stacks-vpc.id

  health_check {
    healthy_threshold   = "2"
    unhealthy_threshold = "3"
    timeout             = "10"
    interval            = "15"
    protocol            = "HTTP"
    matcher             = "200"
    path                = "/"
  }
}

### ALB

resource "aws_lb" "aws-stacks-lb" {
  name               = "aws-stacks-lb"
  load_balancer_type = "application"
  subnets = [
    data.aws_subnets.aws-stacks-subnets.ids[0],
    data.aws_subnets.aws-stacks-subnets.ids[1],
    data.aws_subnets.aws-stacks-subnets.ids[2]
  ]
  security_groups = [
    aws_security_group.aws-stacks-sg-lb.id
  ]
}

resource "aws_lb_listener" "aws-stacks-lb-listener-http" {
  load_balancer_arn = aws_lb.aws-stacks-lb.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.aws-stacks-lb-target-group-http.id
    type             = "forward"
  }
}

resource "aws_autoscaling_attachment" "aws-stacks-asg-attachment" {
  autoscaling_group_name = aws_autoscaling_group.aws-stacks-asg.id
  lb_target_group_arn    = aws_lb_target_group.aws-stacks-lb-target-group-http.arn
}
