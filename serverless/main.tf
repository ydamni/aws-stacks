### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "serverless/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### SES

resource "aws_ses_email_identity" "aws-stacks-ses-email-identity-source" {
  email = var.source_email
}

resource "aws_ses_email_identity" "aws-stacks-ses-email-identity-destination" {
  email = var.destination_email
}

### Lambda Execution Role

resource "aws_iam_role" "aws-stacks-lambda-role" {
  name               = "aws-stacks-lambda-role"
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

### IAM Policies

# Generate Logs

resource "aws_iam_policy" "aws-stacks-iam-policy-logs" {
  name        = "aws-stacks-iam-policy-logs"
  path        = "/"
  description = "Generate Logs"
  policy      = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-logs" {
  role       = aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = aws_iam_policy.aws-stacks-iam-policy-logs.arn
}

# Use SES

data "aws_iam_policy" "aws-stacks-iam-policy-ses" {
  arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-ses" {
  role       = aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = data.aws_iam_policy.aws-stacks-iam-policy-ses.arn
}

### Lambda functions

# Send Email with SES

data "archive_file" "zip_the_python_code" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/lambda_function.py"
  output_path = "${path.module}/lambda_functions/email.zip"
}

resource "aws_lambda_function" "aws-stacks-lambda-function-email" {
  filename      = "${path.module}/lambda_functions/email.zip"
  function_name = "email"
  role          = aws_iam_role.aws-stacks-lambda-role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  depends_on  = [aws_iam_role_policy_attachment.aws-stacks-attachment-ses]
}
