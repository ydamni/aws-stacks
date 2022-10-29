resource "aws_s3_bucket" "aws-stacks-s3-bucket" {
  bucket = "aws-stacks-terraform-state"

  tags = {
    Name = "aws-stacks-s3-bucket"
  }
}

resource "aws_s3_bucket_acl" "aws-stacks-s3-bucket-acl" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "aws-stacks-s3-bucket-versioning" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "aws-stacks-dynamodb-table" {
  name         = "aws-stacks-terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "aws-stacks-terraform-state-lock"
  }
}
