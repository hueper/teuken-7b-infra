# Infrastructure — Teuken-7B on SageMaker

Terraform configuration for deploying the [Teuken-7B-instruct](https://huggingface.co/openGPT-X/Teuken-7B-instruct-v0.6) model on AWS SageMaker with automated cost scheduling.

## Architecture

```
SageMaker Endpoint (ml.g5.2xlarge) ← Endpoint Config ← Model ← Custom TGI container (ECR)
                                                                       ↑
Lambda scheduler (EventBridge cron)                          Secrets Manager (HF token)
  stop:  6 PM UTC Mon–Fri (delete endpoint)
  start: 7 AM UTC Mon–Fri (recreate endpoint)
```

The SageMaker endpoint is **ephemeral** — intentionally created and deleted daily by the Lambda scheduler to avoid idle costs (~$1.50/hr). It is not tracked in Terraform state. Everything else (model, endpoint config, ECR, IAM, Lambdas, EventBridge) is long-lived and Terraform-managed.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Docker (for building the inference container)
- A [HuggingFace token](https://huggingface.co/settings/tokens) with access to the gated model

## Deploy

```bash
cd terraform

# 1. Build and push the inference container
bash container/build.sh

# 2. Provision infrastructure
terraform init
terraform apply

# 3. Set the HuggingFace token
aws secretsmanager put-secret-value \
  --secret-id teuken-llm/hf-token \
  --secret-string "hf_YOUR_TOKEN"

# 4. Bootstrap the endpoint (first time only — the scheduler handles it after this)
aws lambda invoke --function-name teuken-llm-start-endpoint --payload '{}' response.json
```

The endpoint takes ~10–15 minutes to reach `InService`.

## Structure

```
infra/
├── terraform/
│   ├── main.tf          Model, endpoint config, ECR, IAM, Secrets Manager
│   ├── lambda.tf        Endpoint scheduler (Lambda + EventBridge)
│   ├── variables.tf
│   ├── container/       Custom TGI Docker image + build script
│   └── lambda/          Start/stop Lambda handlers
```

## Full Shutdown / Destroy

To permanently shut down the system and ensure the endpoint cannot be recreated:

```bash
cd terraform

# 1. Disable the endpoint scheduler (removes Lambdas and schedules)
terraform apply -var="enable_endpoint_scheduler=false"

# 2. Delete the endpoint (if running)
aws sagemaker delete-endpoint --endpoint-name teuken-llm-teuken-endpoint

# 3. Destroy all remaining Terraform-managed resources
terraform destroy
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `eu-west-1` | AWS region |
| `instance_type` | `ml.g5.2xlarge` | SageMaker GPU instance |
| `enable_endpoint_scheduler` | `true` | Auto start/stop |
| `endpoint_start_schedule` | `cron(0 7 ? * MON-FRI *)` | Start time (UTC) |
| `endpoint_stop_schedule` | `cron(0 18 ? * MON-FRI *)` | Stop time (UTC) |
