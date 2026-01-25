#!/bin/bash
set -e

AWS_REGION="${AWS_REGION:-eu-west-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BASE_IMAGE="763104351884.dkr.ecr.${AWS_REGION}.amazonaws.com/huggingface-pytorch-tgi-inference:2.7.0-tgi3.3.6-gpu-py311-cu124-ubuntu22.04"
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/teuken-llm-inference"

echo "Building custom TGI image with Secrets Manager support..."

# Login to AWS ECR (base image)
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin 763104351884.dkr.ecr.${AWS_REGION}.amazonaws.com

# Login to your ECR
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build (linux/amd64 for SageMaker, provenance=false for Docker V2 manifest)
docker build \
    --platform=linux/amd64 \
    --build-arg BASE_IMAGE=${BASE_IMAGE} \
    --provenance=false \
    -t ${ECR_REPO}:latest \
    -f "$(dirname "$0")/Dockerfile" \
    "$(dirname "$0")"

# Push
docker push ${ECR_REPO}:latest

echo "Image pushed to ${ECR_REPO}:latest"
