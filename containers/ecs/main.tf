### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "containers/ecs/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Get VPC

data "aws_vpc" "aws-stacks-vpc" {
  filter {
    name   = "tag:Name"
    values = ["aws-stacks-vpc"]
  }
}

### Get Subnets

data "aws_subnets" "aws-stacks-subnets" {
  filter {
    name   = "tag:Name"
    values = ["aws-stacks-subnet-public-1", "aws-stacks-subnet-public-2", "aws-stacks-subnet-public-3"]
  }
}

### Security Groups

resource "aws_security_group" "aws-stacks-sg-allow-http" {
  name   = "aws-stacks-sg-allow-http"
  vpc_id = data.aws_vpc.aws-stacks-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "aws-stacks-sg-allow-http"
  }
}

### Get Task Execution Role for ECS to use ECR images

data "aws_iam_role" "aws-stacks-ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

### ECS resources

resource "aws_ecs_cluster" "aws-stacks-cluster" {
  name = "aws-stacks-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "aws-stacks-provider" {
  cluster_name       = aws_ecs_cluster.aws-stacks-cluster.name
  capacity_providers = ["FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 1
    capacity_provider = "FARGATE_SPOT"
  }
}

resource "aws_ecs_task_definition" "aws-stacks-td-mysql-phpmyadmin" {
  family                   = "aws-stacks-td-mysql-phpmyadmin"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.aws-stacks-ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "mysql"
      image     = "${var.ecr_registry}/aws-stacks-mysql:latest"
      cpu       = 256
      memory    = 768
      essential = true
      environment = [
        {
          name  = "MYSQL_ROOT_PASSWORD"
          value = var.mysql_root_password
        }
      ]
      portMappings = [
        {
          containerPort = 3306
          hostPort      = 3306
        }
      ]
    },
    {
      name      = "phpmyadmin"
      image     = "${var.ecr_registry}/aws-stacks-phpmyadmin:latest"
      cpu       = 256
      memory    = 256
      essential = true
      environment = [
        {
          name  = "PMA_HOST"
          value = "127.0.0.1"
        },
        {
          name  = "PMA_USER"
          value = "root"
        },
        {
          name  = "PMA_PASSWORD"
          value = var.mysql_root_password
        }
      ]
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "mysql-phpmyadmin" {
  name            = "mysql-phpmyadmin"
  cluster         = aws_ecs_cluster.aws-stacks-cluster.id
  task_definition = aws_ecs_task_definition.aws-stacks-td-mysql-phpmyadmin.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [data.aws_subnets.aws-stacks-subnets.ids[0], data.aws_subnets.aws-stacks-subnets.ids[1], data.aws_subnets.aws-stacks-subnets.ids[2]]
    security_groups  = [aws_security_group.aws-stacks-sg-allow-http.id]
    assign_public_ip = true
  }
}
