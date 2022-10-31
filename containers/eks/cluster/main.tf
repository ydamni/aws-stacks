### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "containers/eks/cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Get Subnets

data "aws_subnets" "aws-stacks-subnets" {
  filter {
    name   = "tag:Name"
    values = ["aws-stacks-subnet-public-1", "aws-stacks-subnet-public-2", "aws-stacks-subnet-public-3"]
  }
}

### EKS resources

resource "aws_iam_role" "aws-stacks-role-eks-cluster" {
  name = "aws-stacks-role-eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "aws-stacks-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.aws-stacks-role-eks-cluster.name
}

resource "aws_iam_role_policy_attachment" "aws-stacks-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.aws-stacks-role-eks-cluster.name
}

resource "aws_eks_cluster" "aws-stacks-eks-cluster" {
  name     = "aws-stacks-eks-cluster"
  role_arn = aws_iam_role.aws-stacks-role-eks-cluster.arn

  vpc_config {
    subnet_ids = [data.aws_subnets.aws-stacks-subnets.ids[0], data.aws_subnets.aws-stacks-subnets.ids[1], data.aws_subnets.aws-stacks-subnets.ids[2]]
  }

  version = "1.22"

  depends_on = [
    aws_iam_role_policy_attachment.aws-stacks-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.aws-stacks-AmazonEKSVPCResourceController,
  ]

  tags = {
    Name = "aws-stacks-eks-cluster"
  }
}

resource "aws_iam_role" "aws-stacks-role-eks-node-group" {
  name = "aws-stacks-role-eks-node-group"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "aws-stacks-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.aws-stacks-role-eks-node-group.name
}

resource "aws_iam_role_policy_attachment" "aws-stacks-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.aws-stacks-role-eks-node-group.name
}

resource "aws_iam_role_policy_attachment" "aws-stacks-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.aws-stacks-role-eks-node-group.name
}

resource "aws_eks_node_group" "aws-stacks-eks-node-group" {
  cluster_name    = aws_eks_cluster.aws-stacks-eks-cluster.name
  node_group_name = "aws-stacks-eks-node-group"
  node_role_arn   = aws_iam_role.aws-stacks-role-eks-node-group.arn
  subnet_ids      = [data.aws_subnets.aws-stacks-subnets.ids[0], data.aws_subnets.aws-stacks-subnets.ids[1], data.aws_subnets.aws-stacks-subnets.ids[2]]
  instance_types  = ["t2.micro"]

  scaling_config {
    desired_size = 3
    max_size     = 6
    min_size     = 3
  }

  depends_on = [
    aws_iam_role_policy_attachment.aws-stacks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.aws-stacks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.aws-stacks-AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = {
    Name = "aws-stacks-eks-node-group"
  }
}
