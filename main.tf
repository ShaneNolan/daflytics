provider "aws" {
  region = "eu-west-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.63.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

locals {
  database_name = "rentServerlessMysql"
}

# AWS SQS
resource "aws_sqs_queue" "rentsearch_sqs" {
  name = "rentsearch"

  message_retention_seconds = 86400 # a day
}

# AWS IAM FOR RENTSEARCH
module "rentsearch_iam_role" {
  source  = "mineiros-io/iam-role/aws"
  version = "~> 0.6.0"

  name = "rentsearch-role"

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

resource "aws_iam_policy" "rentsearch_iam_policy" {
  policy = data.aws_iam_policy_document.rentsearch_iam_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  policy_arn = aws_iam_policy.rentsearch_iam_policy.arn
  role       = module.rentsearch_iam_role.role.name
}

# AWS LAMBDA FOR RENTSEARCH
resource "null_resource" "rentsearch_lambda_build" {
  triggers = {
    handler      = base64sha256(file("${path.module}/rentsearch/rentsearch/main.py"))
    requirements = base64sha256(file("${path.module}/rentsearch/requirements.txt"))
    build        = base64sha256(file("${path.module}/rentsearch/build.py"))
  }

  provisioner "local-exec" {
    command = "python ${path.module}/rentsearch/build.py"
  }
}

data "archive_file" "rentsearch_lambda_dependencies" {
  type        = "zip"
  source_dir  = "${path.module}/rentsearch/rentsearch/"
  output_path = "${path.module}/rentsearch/lambda.zip"

  depends_on = [null_resource.rentsearch_lambda_build]
}


module "rentsearch_lambda" {
  source  = "mineiros-io/lambda-function/aws"
  version = "~> 0.5.0"

  function_name    = "rent-search"
  description      = "Search Limerick property prices on Daft."
  filename         = data.archive_file.rentsearch_lambda_dependencies.output_path
  runtime          = "python3.8"
  handler          = "main.lambda_handler"
  timeout          = 60
  memory_size      = 128
  source_code_hash = data.archive_file.rentsearch_lambda_dependencies.output_base64sha256

  role_arn = module.rentsearch_iam_role.role.arn

  environment_variables = {
    "sqsname" = aws_sqs_queue.rentsearch_sqs.name
  }
}

# CloudWatch Event for rent-search
resource "aws_cloudwatch_event_rule" "every_day_at_eighteen" {
  name                = "every-day-at-18"
  description         = "Fires everyday at 18:00"
  schedule_expression = "cron(0 18 * * ? *)"
}

resource "aws_cloudwatch_event_target" "run_rentsearch_every_day_at_eighteen" {
  rule      = aws_cloudwatch_event_rule.every_day_at_eighteen.name
  target_id = "rentsearch_lambda"
  arn       = module.rentsearch_lambda.function.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_run_rentsearch_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.rentsearch_lambda.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_day_at_eighteen.arn
}

# AWS AURORA SERVERLESS (MYSQL)
resource "random_string" "db_gen_password" {
  length  = 34
  special = false
}

resource "aws_rds_cluster" "aurora_serverless_mysql" {
  #source = "terraform-aws-modules/rds-aurora/aws"

  database_name = local.database_name
  engine        = "aurora-mysql"
  engine_mode   = "serverless"

  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  apply_immediately = true

  master_username = "rentadmin"
  master_password = random_string.db_gen_password.result

  enable_http_endpoint = true

  scaling_configuration {
    auto_pause               = true
    min_capacity             = 1
    max_capacity             = 2
    seconds_until_auto_pause = 300
  }
}
resource "aws_secretsmanager_secret" "rds_credentials" {
  name = "rent_credentials"
}

resource "aws_secretsmanager_secret_version" "serverless_rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = aws_rds_cluster.aurora_serverless_mysql.master_username
    password = random_string.db_gen_password.result
  })
}

output "rds_host" {
  value = aws_rds_cluster.aurora_serverless_mysql.endpoint
}

output "rds_creds" {
  value = "${aws_rds_cluster.aurora_serverless_mysql.master_username}/${random_string.db_gen_password.result}"
}

# AWS IAM FOR RENTEXTRACT
module "rentextract_iam_role" {
  source  = "mineiros-io/iam-role/aws"
  version = "~> 0.6.0"

  name = "rentextact-role"

  assume_role_principals = [
    {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  ]
}

data "aws_iam_policy_document" "rentextract_iam_policy" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = [aws_sqs_queue.rentsearch_sqs.arn]

    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "RDSDataServiceAccess"
    effect    = "Allow"
    resources = [aws_rds_cluster.aurora_serverless_mysql.arn]

    actions = [
      "rds-data:BatchExecuteStatement",
      "rds-data:BeginTransaction",
      "rds-data:CommitTransaction",
      "rds-data:ExecuteStatement",
      "rds-data:RollbackTransaction"
    ]
  }

  statement {
    sid       = "SecretsManagerDbCredentialsAccess"
    effect    = "Allow"
    resources = [aws_secretsmanager_secret.rds_credentials.arn]

    actions = [
      "secretsmanager:GetSecretValue",
    ]
  }

  statement {
    sid       = "AllowCreatingLogGroups"
    effect    = "Allow"
    resources = ["arn:aws:logs:eu-west-1:*:*"]
    actions   = ["logs:CreateLogGroup"]
  }

  statement {
    sid       = "AllowWritingLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:eu-west-1:*:log-group:/aws/lambda/*:*"]

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

resource "aws_iam_policy" "rentextract_iam_policy" {
  policy = data.aws_iam_policy_document.rentextract_iam_policy.json
}

resource "aws_iam_role_policy_attachment" "rentextract_attach_policy" {
  policy_arn = aws_iam_policy.rentextract_iam_policy.arn
  role       = module.rentextract_iam_role.role.name
}

# AWS LAMBDA FOR RENTEXTRACT
resource "null_resource" "rentextract_lambda_build" {
  triggers = {
    handler      = base64sha256(file("${path.module}/rentextract/rentextract/main.py"))
    requirements = base64sha256(file("${path.module}/rentextract/requirements.txt"))
    build        = base64sha256(file("${path.module}/rentextract/build.py"))
  }

  provisioner "local-exec" {
    command = "python ${path.module}/rentextract/build.py"
  }
}

data "archive_file" "rentextract_lambda_dependencies" {
  type        = "zip"
  source_dir  = "${path.module}/rentextract/rentextract/"
  output_path = "${path.module}/rentextract/lambda.zip"

  depends_on = [null_resource.rentextract_lambda_build]
}


module "rentextract_lambda" {
  source  = "mineiros-io/lambda-function/aws"
  version = "~> 0.5.0"

  function_name    = "rent-extract"
  description      = "Extract property informations from SQS."
  filename         = data.archive_file.rentextract_lambda_dependencies.output_path
  runtime          = "python3.8"
  handler          = "main.lambda_handler"
  timeout          = 30
  memory_size      = 128
  source_code_hash = data.archive_file.rentextract_lambda_dependencies.output_base64sha256

  role_arn = module.rentextract_iam_role.role.arn

  environment_variables = {
    "clusterarn" = aws_rds_cluster.aurora_serverless_mysql.arn,
    "secretarn"  = aws_secretsmanager_secret_version.serverless_rds_credentials.arn
    "database"   = local.database_name,
  }
}

# AWS EVENT SOURCE MAPPING FOR RENTEXTRACT
resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  batch_size       = 1
  event_source_arn = aws_sqs_queue.rentsearch_sqs.arn
  enabled          = true
  function_name    = module.rentextract_lambda.function.arn
}
