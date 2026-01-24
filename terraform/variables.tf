variable "aws_region" {
  description = "AWS region for deployment"
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name prefix for resources"
  default     = "teuken-llm"
}

variable "instance_type" {
  description = "SageMaker instance type"
  default     = "ml.g5.2xlarge"
}

variable "huggingface_inference_image" {
  description = "HuggingFace LLM TGI image URI (version 3.3.6)"
  default     = "763104351884.dkr.ecr.eu-west-1.amazonaws.com/huggingface-pytorch-tgi-inference:2.7.0-tgi3.3.6-gpu-py311-cu124-ubuntu22.04"
}

variable "hf_token" {
  description = "HuggingFace API token for gated model access"
  type        = string
  sensitive   = true
}
