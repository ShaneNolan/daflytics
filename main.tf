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
