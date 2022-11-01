### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "containers/ecr/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

resource "aws_ecr_repository" "aws-stacks-ecr-repository-mysql" {
  name                 = "aws-stacks-mysql"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "aws-stacks-ecr-repository-mysql"
  }
}

resource "aws_ecr_repository" "aws-stacks-ecr-repository-phpmyadmin" {
  name                 = "aws-stacks-phpmyadmin"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "aws-stacks-ecr-repository-phpmyadmin"
  }
}
