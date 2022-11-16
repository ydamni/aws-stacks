### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "database/dynamodb/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### DynamoDB

resource "aws_dynamodb_table" "aws-stacks-dynamodb-table" {
  name         = "aws-stacks-serverless-logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "destination"
  table_class  = "STANDARD_INFREQUENT_ACCESS"

  attribute {
    name = "destination"
    type = "S"
  }

  tags = {
    Name = "aws-stacks-dynamodb-table"
  }
}

### Lambda Functions
## Lambda Functions will be updated via awscli (See Gitlab CI)

# Link DynamoDB Full Access Policy to Lambda Role

data "aws_iam_role" "aws-stacks-lambda-role" {
  name = "aws-stacks-lambda-role"
}

data "aws_iam_policy" "aws-stacks-iam-policy-dynamodb" {
  arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws-stacks-attachment-dynamodb" {
  role       = data.aws_iam_role.aws-stacks-lambda-role.name
  policy_arn = data.aws_iam_policy.aws-stacks-iam-policy-dynamodb.arn
}

# Store logs in DynamoDB when SES is used

resource "local_file" "aws-stacks-file-lambda-email" {
  filename = "${path.module}/ses/lambda_function.py"
  content  = <<EOF
import boto3
from datetime import datetime

ses = boto3.client('ses')
dynamodb = boto3.client('dynamodb')

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
    dynamodb.put_item(
        TableName='${aws_dynamodb_table.aws-stacks-dynamodb-table.name}',
        Item={
            'timestamp': {
                'S': str(datetime.now().timestamp())
            },
            'date': {
                'S': str(datetime.now().isoformat(timespec='seconds'))
            },
            'typeOfSending': {
                'S': 'email'
            },
            'destination': {
                'S': event['destinationEmail']
            }
        }
    )
    return 'Email sent!'
EOF

}

data "archive_file" "aws-stacks-zip-lambda-email" {
  type        = "zip"
  source_file = "${path.module}/ses/lambda_function.py"
  output_path = "${path.module}/ses/email.zip"

  depends_on = [local_file.aws-stacks-file-lambda-email]
}

# Store logs in DynamoDB when SNS is used

resource "local_file" "aws-stacks-file-lambda-sms" {
  filename = "${path.module}/sns/lambda_function.py"
  content  = <<EOF
import boto3
from datetime import datetime

sns = boto3.client('sns')
dynamodb = boto3.client('dynamodb')

def lambda_handler(event, context):
    sns.publish(
        PhoneNumber=event['phoneNumber'],
        Message=event['message']
    )
    dynamodb.put_item(
        TableName='aws-stacks-serverless-logs',
        Item={
            'timestamp': {
                'S': str(datetime.now().timestamp())
            },
            'date': {
                'S': str(datetime.now().isoformat(timespec='seconds'))
            },
            'typeOfSending': {
                'S': 'sms'
            },
            'destination': {
                'S': event['phoneNumber']
            }
        }
    )
    return 'SMS sent!'
EOF

}

data "archive_file" "aws-stacks-zip-lambda-sms" {
  type        = "zip"
  source_file = "${path.module}/sns/lambda_function.py"
  output_path = "${path.module}/sns/sms.zip"

  depends_on = [local_file.aws-stacks-file-lambda-sms]
}
