terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Secrets Manager for HuggingFace Token
# -----------------------------------------------------------------------------

# Secret placeholder - value must be set manually in AWS Console or CLI
# This ensures the token never appears in Terraform state
resource "aws_secretsmanager_secret" "hf_token" {
  name        = "${var.project_name}/hf-token"
  description = "HuggingFace API token for gated model access. Set value manually."
}

# -----------------------------------------------------------------------------
# ECR Repository for Custom Container
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "teuken_inference" {
  name                 = "${var.project_name}-inference"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM Role for SageMaker
resource "aws_iam_role" "sagemaker_role" {
  name = "${var.project_name}-sagemaker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "sagemaker.amazonaws.com"
      }
    }]
  })
}

# Least-privilege inline policy for SageMaker execution role
resource "aws_iam_role_policy" "sagemaker_execution" {
  name = "${var.project_name}-sagemaker-execution-policy"
  role = aws_iam_role.sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPullImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:763104351884:repository/*",
          aws_ecr_repository.teuken_inference.arn
        ]
      },
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/sagemaker/*"
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.hf_token.arn
      }
    ]
  })
}

# Wait for IAM role propagation
resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy.sagemaker_execution]
  create_duration = "30s"
}

# SageMaker Model
resource "aws_sagemaker_model" "teuken" {
  name               = "${var.project_name}-teuken-7b"
  execution_role_arn = aws_iam_role.sagemaker_role.arn
  depends_on         = [time_sleep.iam_propagation]

  primary_container {
    # Custom image that fetches HF_TOKEN from Secrets Manager at runtime
    image = "${aws_ecr_repository.teuken_inference.repository_url}:${var.image_tag}"
    environment = {
      HF_MODEL_ID              = "openGPT-X/Teuken-7B-instruct-v0.6"
      HF_TOKEN_SECRET_ARN      = aws_secretsmanager_secret.hf_token.arn
      AWS_REGION               = var.aws_region
      SM_NUM_GPUS              = "1"
      TRUST_REMOTE_CODE        = "true"
      HF_HUB_TRUST_REMOTE_CODE = "true"
    }
  }
}

# The endpoint is intentionally ephemeral: created/deleted by the Lambda scheduler.
# Terraform manages the endpoint configuration but NOT the endpoint itself.
# BOOTSTRAP: After first `terraform apply`, create the endpoint by invoking:
#   aws lambda invoke --function-name teuken-llm-start-endpoint --payload '{}' /dev/stdout
locals {
  endpoint_name        = "${var.project_name}-teuken-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.teuken.name
}

# SageMaker Endpoint Configuration
resource "aws_sagemaker_endpoint_configuration" "teuken" {
  name = "${var.project_name}-teuken-config"

  production_variants {
    variant_name                           = "primary"
    model_name                             = aws_sagemaker_model.teuken.name
    initial_instance_count                 = 1
    instance_type                          = var.instance_type
    container_startup_health_check_timeout_in_seconds = 900
  }
}

# Outputs
output "endpoint_name" {
  description = "SageMaker endpoint name (lifecycle managed by Lambda scheduler, not Terraform)"
  value       = local.endpoint_name
}

output "hf_token_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the HuggingFace token"
  value       = aws_secretsmanager_secret.hf_token.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the custom inference image"
  value       = aws_ecr_repository.teuken_inference.repository_url
}
