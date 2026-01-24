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

resource "aws_iam_role_policy_attachment" "sagemaker_full" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy_attachment" "s3_read" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Wait for IAM role propagation
resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy_attachment.sagemaker_full, aws_iam_role_policy_attachment.s3_read]
  create_duration = "30s"
}

# SageMaker Model
resource "aws_sagemaker_model" "teuken" {
  name               = "${var.project_name}-teuken-7b"
  execution_role_arn = aws_iam_role.sagemaker_role.arn
  depends_on         = [time_sleep.iam_propagation]

  primary_container {
    image = var.huggingface_inference_image
    environment = {
      HF_MODEL_ID             = "openGPT-X/Teuken-7B-instruct-v0.6"
      HF_TOKEN                = var.hf_token
      SM_NUM_GPUS             = "1"
      TRUST_REMOTE_CODE       = "true"
      HF_HUB_TRUST_REMOTE_CODE = "true"
    }
  }
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

# SageMaker Endpoint
resource "aws_sagemaker_endpoint" "teuken" {
  name                 = "${var.project_name}-teuken-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.teuken.name
}

# Outputs
output "endpoint_name" {
  value = aws_sagemaker_endpoint.teuken.name
}
