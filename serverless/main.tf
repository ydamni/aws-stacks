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

## SES

# Link SES Full Access Policy to Lambda Role

data "aws_iam_policy" "aws-stacks-iam-policy-ses" {
  arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-ses" {
  role       = aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = data.aws_iam_policy.aws-stacks-iam-policy-ses.arn
}

# Send Email with SES

resource "local_file" "aws-stacks-file-lambda-email" {
  filename = "${path.module}/lambda_functions/ses/lambda_function.py"
  content  = <<EOF
import boto3

ses = boto3.client('ses')

def lambda_handler(event, context):
    ses.send_email(
        Source='${var.source_email}',
        Destination={
            'ToAddresses': [
                event['destinationEmail'],
            ]
        },
        Message={
            'Subject': {
                'Data': 'AWS Stacks - Serverless'
            },
            'Body': {
                'Text': {
                    'Data': event['message']
                }
            }
        }
    )
    return 'Email sent!'
EOF

}

data "archive_file" "aws-stacks-zip-lambda-email" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/ses/lambda_function.py"
  output_path = "${path.module}/lambda_functions/ses/email.zip"

  depends_on = [local_file.aws-stacks-file-lambda-email]
}

resource "aws_lambda_function" "aws-stacks-lambda-function-email" {
  filename      = "${path.module}/lambda_functions/ses/email.zip"
  function_name = "email"
  role          = aws_iam_role.aws-stacks-lambda-role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  depends_on = [aws_iam_role_policy_attachment.aws-stacks-attachment-ses, data.archive_file.aws-stacks-zip-lambda-email]
}

## SNS

# Link SNS Full Access Policy to Lambda Role

data "aws_iam_policy" "aws-stacks-iam-policy-sns" {
  arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-sns" {
  role       = aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = data.aws_iam_policy.aws-stacks-iam-policy-sns.arn
}

# Send SMS with SNS

resource "local_file" "aws-stacks-file-lambda-sms" {
  filename = "${path.module}/lambda_functions/sns/lambda_function.py"
  content  = <<EOF
import boto3

sns = boto3.client('sns')

def lambda_handler(event, context):
    sns.publish(
        PhoneNumber=event['phoneNumber'],
        Message=event['message']
    )
    return 'SMS sent!'
EOF

}

data "archive_file" "aws-stacks-zip-lambda-sms" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/sns/lambda_function.py"
  output_path = "${path.module}/lambda_functions/sns/sms.zip"

  depends_on = [local_file.aws-stacks-file-lambda-sms]
}

resource "aws_lambda_function" "aws-stacks-lambda-function-sms" {
  filename      = "${path.module}/lambda_functions/sns/sms.zip"
  function_name = "sms"
  role          = aws_iam_role.aws-stacks-lambda-role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  depends_on = [aws_iam_role_policy_attachment.aws-stacks-attachment-sns, data.archive_file.aws-stacks-zip-lambda-sms]
}

### Step Functions

# Create Role & Policy for Step Functions

resource "aws_iam_role" "aws-stacks-iam-role-sfn" {
  name               = "aws-stacks-iam-role-sfn"
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

### Lambda Function for REST API

## Rest API Handler

# Link Step Functions Full Access Policy to Lambda Role

data "aws_iam_policy" "aws-stacks-iam-policy-sfn" {
  arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-api" {
  role       = aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = data.aws_iam_policy.aws-stacks-iam-policy-sfn.arn
}

# Send events from API to Step Functions

resource "local_file" "aws-stacks-api-handler" {
  filename = "${path.module}/lambda_functions/api/lambda_function.py"
  content  = <<EOF
import boto3
import json

sfn = boto3.client('stepfunctions')

def lambda_handler(event, context):
    sfn.start_execution(
        stateMachineArn="${aws_sfn_state_machine.aws-stacks-sfn-state-machine.arn}",
        input=event['body']
    )
    
    return {
        "statusCode": 200,
        "body": json.dumps(
            {"Status": "Instruction sent to the REST API Handler!"},
        )
    }
EOF

  depends_on = [aws_sfn_state_machine.aws-stacks-sfn-state-machine]
}

data "archive_file" "aws-stacks-zip-lambda-api" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/api/lambda_function.py"
  output_path = "${path.module}/lambda_functions/api/api.zip"

  depends_on = [local_file.aws-stacks-api-handler]
}

resource "aws_lambda_function" "aws-stacks-lambda-function-api" {
  filename      = "${path.module}/lambda_functions/api/api.zip"
  function_name = "rest_api_handler"
  role          = aws_iam_role.aws-stacks-lambda-role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  depends_on = [aws_iam_role_policy_attachment.aws-stacks-attachment-api, data.archive_file.aws-stacks-zip-lambda-api]
}

### API Gateway resources

resource "aws_lambda_permission" "aws-stacks-lambda-permission-api-gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aws-stacks-lambda-function-api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.account_id}:${aws_api_gateway_rest_api.aws-stacks-api-gateway-rest.id}/*/${aws_api_gateway_method.aws-stacks-api-gateway-method.http_method}${aws_api_gateway_resource.aws-stacks-api-gateway-resource.path}"
}

resource "aws_api_gateway_rest_api" "aws-stacks-api-gateway-rest" {
  name        = "aws-stacks-rest-api-gateway"
  description = "REST API for sending Email & SMS"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "aws-stacks-api-gateway-resource" {
  rest_api_id = aws_api_gateway_rest_api.aws-stacks-api-gateway-rest.id
  parent_id   = aws_api_gateway_rest_api.aws-stacks-api-gateway-rest.root_resource_id
  path_part   = "sending"

  depends_on = [aws_api_gateway_rest_api.aws-stacks-api-gateway-rest]
}

resource "aws_api_gateway_method" "aws-stacks-api-gateway-method" {
  rest_api_id   = aws_api_gateway_rest_api.aws-stacks-api-gateway-rest.id
  resource_id   = aws_api_gateway_resource.aws-stacks-api-gateway-resource.id
  http_method   = "POST"
  authorization = "NONE"

  depends_on = [aws_api_gateway_resource.aws-stacks-api-gateway-resource]
}

resource "aws_api_gateway_integration" "aws-stacks-api-gateway-integration" {
  rest_api_id             = aws_api_gateway_rest_api.aws-stacks-api-gateway-rest.id
  resource_id             = aws_api_gateway_resource.aws-stacks-api-gateway-resource.id
  http_method             = aws_api_gateway_method.aws-stacks-api-gateway-method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.aws-stacks-lambda-function-api.invoke_arn

  depends_on = [aws_api_gateway_method.aws-stacks-api-gateway-method]
}

resource "aws_api_gateway_deployment" "aws-stacks-api-gateway-deployment" {
  rest_api_id = aws_api_gateway_rest_api.aws-stacks-api-gateway-rest.id

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.aws-stacks-api-gateway-integration]
}

resource "aws_api_gateway_stage" "aws-stacks-api-gateway-stage" {
  deployment_id = aws_api_gateway_deployment.aws-stacks-api-gateway-deployment.id
  rest_api_id   = aws_api_gateway_rest_api.aws-stacks-api-gateway-rest.id
  stage_name    = "sendingStage"
}

### Static Web Hosting

# Website files

resource "local_file" "aws-stacks-website-index" {
  filename = "${path.module}/website/s3/index.html"
  content  = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Project 2 - Cloud Is Free</title>
    <script src="formToApi.js"></script>
</head>
<body>
    <form>
        <div>
            <label>Message:</label>
            <input type="text" name="message">
            <br><br>
            <label>Email:</label>
            <input name="email">
            <button onClick="formToApi(event,'email')">Send an Email</button>
            <br><br>
            <label>SMS:</label>
            <input name="sms">
            <button onClick="formToApi(event,'sms')">Send a SMS</button>
        </div>
    </form>
</body>
</html>
EOF
}

resource "local_file" "aws-stacks-website-formtoapi" {
  filename = "${path.module}/website/s3/formToApi.js"
  content  = <<EOF
function formToApi(event, typeOfSending) {

    event.preventDefault()

    var data = {
        typeOfSending: typeOfSending,
        destinationEmail: document.getElementsByName('email')[0].value,
        phoneNumber: document.getElementsByName('sms')[0].value,
        message: document.getElementsByName('message')[0].value
    }

    fetch( "${aws_api_gateway_stage.aws-stacks-api-gateway-stage.invoke_url}/${aws_api_gateway_resource.aws-stacks-api-gateway-resource.path_part}" , {
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify(data),
        mode: "no-cors"
    })
}
EOF

  depends_on = [aws_api_gateway_stage.aws-stacks-api-gateway-stage, aws_api_gateway_resource.aws-stacks-api-gateway-resource]
}

# S3 resources

resource "aws_s3_bucket" "aws-stacks-s3-bucket" {
  bucket = "aws-stacks-serverless-s3-bucket"
}

resource "aws_s3_bucket_acl" "aws-stacks-s3-bucket-acl" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id
  acl    = "public-read"
}

resource "aws_s3_bucket_policy" "aws-stacks-s3-bucket-policy" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.aws-stacks-s3-bucket.bucket}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_s3_bucket_website_configuration" "aws-stacks-s3-bucket-web-conf" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_object" "aws-stacks-s3-object-index" {
  bucket       = aws_s3_bucket.aws-stacks-s3-bucket.id
  key          = "index.html"
  source       = "${path.module}/website/s3/index.html"
  acl          = "public-read"
  content_type = "text/html"

  depends_on = [local_file.aws-stacks-website-index]
}

resource "aws_s3_object" "aws-stacks-s3-object-formtoapi" {
  bucket       = aws_s3_bucket.aws-stacks-s3-bucket.id
  key          = "formToApi.js"
  source       = "${path.module}/website/s3/formToApi.js"
  acl          = "public-read"
  content_type = "text/html"

  depends_on = [local_file.aws-stacks-website-formtoapi]
}
