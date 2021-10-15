provider "aws" {
  region = "eu-west-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

# AWS SQS
resource "aws_sqs_queue" "rentsearch_sqs" {
  name = "rentsearch"

  message_retention_seconds = 86400 # a day
}

# output "rentsearch_sqs_arn" {
#   value = aws_sqs_queue.rentsearch_sqs.arn
# }

resource "null_resource" "lambda_build" {
  triggers = {
    handler      = base64sha256(file("${path.module}/rentsearch/rentsearch/lambda.py"))
    requirements = base64sha256(file("${path.module}/rentsearch/requirements.txt"))
    build        = base64sha256(file("${path.module}/rentsearch/build.py"))
  }

  provisioner "local-exec" {
    command = "python ${path.module}/rentsearch/build.py"
  }
}

data "archive_file" "lambda_with_dependencies" {
  type        = "zip"
  source_dir  = "${path.module}/rentsearch/rentsearch/"
  output_path = "${path.module}/rentsearch/lambda.zip"

  depends_on = [null_resource.lambda_build]
}


module "iam_role" {
  source  = "mineiros-io/iam-role/aws"
  version = "~> 0.6.0"

  name = "rent-search"

  assume_role_principals = [
    {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  ]
}

data "aws_iam_policy_document" "rentsearch_iam_policy" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = [aws_sqs_queue.rentsearch_sqs.arn]

    actions = [
      "sqs:ListQueues",
      "sqs:ListQueueTags",
      "sqs:GetQueueUrl",
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
  }
}

resource "aws_iam_policy" "rentserach_iam_policy" {
  policy = data.aws_iam_policy_document.rentsearch_iam_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  policy_arn = aws_iam_policy.rentserach_iam_policy.arn
  role       = module.iam_role.role.name
}

module "lambda-function" {
  source  = "mineiros-io/lambda-function/aws"
  version = "~> 0.5.0"

  function_name    = "rent-search"
  description      = "Search Limerick property prices on Daft."
  filename         = data.archive_file.lambda_with_dependencies.output_path
  runtime          = "python3.8"
  handler          = "lambda.lambda_handler"
  timeout          = 30
  memory_size      = 128
  source_code_hash = data.archive_file.lambda_with_dependencies.output_base64sha256

  role_arn = module.iam_role.role.arn

  environment_variables = {
    "sqsname" = aws_sqs_queue.rentsearch_sqs.name
  }
}
