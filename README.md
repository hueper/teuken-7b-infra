# Infrastructure — Teuken-7B on SageMaker

Terraform configuration for deploying the [Teuken-7B-instruct](https://huggingface.co/openGPT-X/Teuken-7B-instruct-v0.6) model on AWS SageMaker with automated cost scheduling.

## Architecture

```
SageMaker Endpoint (ml.g5.2xlarge) ← Endpoint Config ← Model ← Custom TGI container (ECR)
                                                                       ↑
Lambda scheduler (EventBridge cron)                          Secrets Manager (HF token)
  stop:  6 PM UTC Mon–Fri (delete endpoint)
  start: 7 AM UTC Mon–Fri (recreate endpoint)

GitHub Actions (OIDC) → builds and pushes container image to ECR on merge to main
```

The SageMaker endpoint is **ephemeral** — intentionally created and deleted daily by the Lambda scheduler to avoid idle costs (~$1.50/hr). It is not tracked in Terraform state. Everything else (model, endpoint config, ECR, IAM, Lambdas, EventBridge) is long-lived and Terraform-managed.

Container images are built by CI and tagged with the Git SHA. Local Docker builds are not required.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- A [HuggingFace token](https://huggingface.co/settings/tokens) with access to the gated model

## Deploy

```bash
cd terraform

# 1. Provision base infrastructure (creates ECR, OIDC provider, CI role)
terraform init
terraform apply \
  -target=aws_ecr_repository.teuken_inference \
  -target=aws_iam_openid_connect_provider.github \
  -target=aws_iam_role.github_actions \
  -target=aws_iam_role_policy.github_actions_ecr

# 2. Set AWS_ROLE_ARN secret in GitHub repo settings
#    (value from: terraform output github_actions_role_arn)

# 3. Push to main (or trigger workflow manually) to build the image

# 4. Provision remaining infrastructure with the image tag from CI
terraform apply -var="image_tag=<git-sha>"

# 5. Set the HuggingFace token
aws secretsmanager put-secret-value \
  --secret-id teuken-llm/hf-token \
  --secret-string "hf_YOUR_TOKEN"

# 6. Bootstrap the endpoint (first time only — the scheduler handles it after this)
aws lambda invoke --function-name teuken-llm-start-endpoint --payload '{}' response.json
```

> **Note:** The `-target` apply in step 1 is a one-time bootstrap to break the circular dependency (CI needs ECR + OIDC role to push, Terraform needs an image tag to create the model). After the first image is pushed, all subsequent deploys use a normal `terraform apply`.

The endpoint takes ~10–15 minutes to reach `InService`.

## Structure

```
infra/
├── .github/workflows/
│   └── build-image.yml  CI: build and push container image to ECR
├── terraform/
│   ├── main.tf          Model, endpoint config, ECR, IAM, Secrets Manager
│   ├── lambda.tf        Endpoint scheduler (Lambda + EventBridge)
│   ├── ci.tf            GitHub OIDC provider + CI IAM role
│   ├── variables.tf
│   ├── container/       Dockerfile + entrypoint for TGI inference
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
| `image_tag` | *(required)* | Container image tag (Git SHA from CI) |
| `github_repo` | *(required)* | GitHub repository (org/repo) for OIDC trust |
| `aws_region` | `eu-west-1` | AWS region |
| `instance_type` | `ml.g5.2xlarge` | SageMaker GPU instance |
| `enable_endpoint_scheduler` | `true` | Auto start/stop |
| `endpoint_start_schedule` | `cron(0 7 ? * MON-FRI *)` | Start time (UTC) |
| `endpoint_stop_schedule` | `cron(0 18 ? * MON-FRI *)` | Stop time (UTC) |
