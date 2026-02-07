#!/bin/bash
set -e

if [ -n "$HF_TOKEN_SECRET_ARN" ]; then
  echo "Fetching HuggingFace token from Secrets Manager..."
  export HF_TOKEN=$(aws secretsmanager get-secret-value \
    --secret-id "$HF_TOKEN_SECRET_ARN" \
    --query 'SecretString' \
    --output text \
    --region "${AWS_REGION:-eu-central-1}")
fi

exec /usr/local/bin/text-generation-launcher \
  --model-id "${HF_MODEL_ID}" \
  --num-shard "${SM_NUM_GPUS:-1}" \
  --port 8080
