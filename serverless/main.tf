### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "serverless/ses/terraform.tfstate"
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
