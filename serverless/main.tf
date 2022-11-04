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

### Lambda functions

# Link SES Full Access Policy to Lambda Role

data "aws_iam_policy" "aws-stacks-iam-policy-ses" {
  arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-ses" {
  role       = aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = data.aws_iam_policy.aws-stacks-iam-policy-ses.arn
}

# Send Email with SES

data "archive_file" "aws-stacks-zip-lambda-email" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/ses/lambda_function.py"
  output_path = "${path.module}/lambda_functions/ses/email.zip"
}

resource "aws_lambda_function" "aws-stacks-lambda-function-email" {
  filename      = "${path.module}/lambda_functions/ses/email.zip"
  function_name = "email"
  role          = aws_iam_role.aws-stacks-lambda-role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  depends_on = [aws_iam_role_policy_attachment.aws-stacks-attachment-ses]
}

# Link SNS Full Access Policy to Lambda Role

data "aws_iam_policy" "aws-stacks-iam-policy-sns" {
  arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-sns" {
  role       = aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = data.aws_iam_policy.aws-stacks-iam-policy-sns.arn
}

# Send SMS with SNS

data "archive_file" "aws-stacks-zip-lambda-sms" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/sns/lambda_function.py"
  output_path = "${path.module}/lambda_functions/sns/sms.zip"
}

resource "aws_lambda_function" "aws-stacks-lambda-function-sms" {
  filename      = "${path.module}/lambda_functions/sns/sms.zip"
  function_name = "sms"
  role          = aws_iam_role.aws-stacks-lambda-role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  depends_on = [aws_iam_role_policy_attachment.aws-stacks-attachment-sns]
}

### Step Functions

# Create Role & Policy for Step Functions

resource "aws_iam_role" "aws-stacks-iam-role-sfn" {
name   = "aws-stacks-iam-role-sfn"
assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "states.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_policy" "aws-stacks-iam-policy-sfn" {
  name        = "aws-stacks-iam-policy-sfn"
  path        = "/"
  description = "Authorize Step Functions to Invoke Lambda Functions"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${aws_lambda_function.aws-stacks-lambda-function-email.function_name}:*",
                "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${aws_lambda_function.aws-stacks-lambda-function-sms.function_name}:*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${aws_lambda_function.aws-stacks-lambda-function-email.function_name}",
                "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${aws_lambda_function.aws-stacks-lambda-function-sms.function_name}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-sfn" {
  role       = aws_iam_role.aws-stacks-iam-role-sfn.name
  policy_arn = aws_iam_policy.aws-stacks-iam-policy-sfn.arn
}

# Create State Machine

resource "aws_sfn_state_machine" "aws-stacks-sfn-state-machine" {
  name     = "aws-stacks-sfn-state-machine"
  role_arn = aws_iam_role.aws-stacks-iam-role-sfn.arn

  definition = <<EOF
{
    "Comment": "State machine for sending SMS & email",
    "StartAt": "Select Type of Sending",
    "States": {
        "Select Type of Sending": {
            "Type": "Choice",
            "Choices": [
                {
                    "Variable": "$.typeOfSending",
                    "StringEquals": "email",
                    "Next": "Email"
                },
                {
                    "Variable": "$.typeOfSending",
                    "StringEquals": "sms",
                    "Next": "SMS"
                }
            ]
        },
        "Email": {
            "Type" : "Task",
            "Resource": "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${aws_lambda_function.aws-stacks-lambda-function-email.function_name}",
            "End": true
        },
        "SMS": {
            "Type" : "Task",
            "Resource": "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${aws_lambda_function.aws-stacks-lambda-function-sms.function_name}",
            "End": true
        }
    }
}
EOF
}
