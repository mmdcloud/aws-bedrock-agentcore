# 🌦️ Weather Agent — AWS Bedrock AgentCore

> A production-ready, containerized AI Weather Agent powered by **Amazon Bedrock AgentCore** — with persistent memory, browser tool, code interpreter, and full observability. Infrastructure fully automated with Terraform.

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Amazon Bedrock](https://img.shields.io/badge/Amazon%20Bedrock-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Python](https://img.shields.io/badge/Python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54)

---

## 📖 Overview

This project provisions a fully autonomous AI weather agent on AWS using **Amazon Bedrock AgentCore**. The agent runs inside a Docker container and is capable of:

- Fetching and reasoning about real-time weather data via a **Browser tool**
- Executing dynamic weather analysis scripts via a **Code Interpreter**
- Remembering user activity preferences across sessions via **AgentCore Memory**
- Writing results and generated artifacts to S3

The entire infrastructure — VPC, ECR, IAM, CodeBuild CI/CD pipeline, AgentCore runtime, and observability stack — is defined and provisioned as code using Terraform.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            AWS Account                                   │
│                                                                          │
│   ┌──────────────┐    ┌──────────────┐    ┌───────────────────────────┐ │
│   │   S3 Bucket  │    │   S3 Bucket  │    │       CodeBuild           │ │
│   │ Agent Source │───▶│   (Results)  │    │  ARM64 Docker Image Build │ │
│   └──────────────┘    └──────┬───────┘    └──────────┬────────────────┘ │
│                              │                        │ push image        │
│                              │            ┌───────────▼────────────────┐ │
│                              │            │     Amazon ECR             │ │
│                              │            │  (Immutable Tags,          │ │
│                              │            │   Last 5 Images Policy)    │ │
│                              │            └───────────┬────────────────┘ │
│                              │                        │ pull image        │
│   ┌──────────────────────────▼────────────────────────▼────────────────┐ │
│   │                  Bedrock AgentCore Runtime                         │ │
│   │                                                                    │ │
│   │   ┌─────────────┐  ┌──────────────────┐  ┌──────────────────┐    │ │
│   │   │   Browser   │  │ Code Interpreter │  │  AgentCore Memory│    │ │
│   │   │    Tool     │  │      Tool        │  │ (Activity Prefs) │    │ │
│   │   └─────────────┘  └──────────────────┘  └──────────────────┘    │ │
│   │                                                                    │ │
│   │              ┌──────────────────────────────┐                     │ │
│   │              │   Amazon Bedrock LLM          │                     │ │
│   │              │  (InvokeModel / Streaming)    │                     │ │
│   │              └──────────────────────────────┘                     │ │
│   └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                     Observability                                │  │
│   │   CloudWatch Logs (14-day retention)  ◄──────── Application Logs│  │
│   │   AWS X-Ray Traces ◄──────────────────────────── Traces         │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │   VPC  (10.0.0.0/16) │ Public + Private Subnets │ NAT per AZ    │  │
│   └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🔧 AWS Services Provisioned

| Service | Purpose |
|---|---|
| **Amazon Bedrock AgentCore Runtime** | Hosts and executes the containerized weather agent |
| **AgentCore Memory** | Persists user activity preferences across agent sessions |
| **AgentCore Browser** | Enables the agent to browse the web for live weather data |
| **AgentCore Code Interpreter** | Enables the agent to write and execute weather analysis code |
| **Amazon ECR** | Stores Docker images with immutable tags; keeps only the last 5 |
| **AWS CodeBuild** | ARM64 CI/CD pipeline to build and push the agent Docker image |
| **Amazon S3 (Source)** | Stores agent source code consumed by CodeBuild |
| **Amazon S3 (Results)** | Stores agent-generated artifacts and weather reports |
| **VPC** | Isolated network with public/private subnets and one NAT gateway per AZ |
| **IAM** | Scoped execution roles for AgentCore runtime and CodeBuild |
| **CloudWatch Logs** | Application log delivery with 14-day retention |
| **AWS X-Ray** | Distributed tracing for agent runtime calls |

---

## 📁 Project Structure

```
weather-agent/
├── main.tf                         # Root module — orchestrates all resources
├── variables.tf                    # Input variable declarations
├── outputs.tf                      # Output values (runtime ARN, S3 buckets, etc.)
├── provider.tf                     # AWS provider configuration
├── scripts/
│   ├── build-image.sh              # Docker build and ECR push script
│   ├── buildspec.yml               # CodeBuild build specification
│   └── init-memory.py              # Seeds AgentCore Memory with activity preferences
├── modules/
│   ├── vpc/                        # VPC, subnets, IGW, NAT gateways
│   ├── ecr/                        # ECR repository with lifecycle and repository policy
│   ├── s3/                         # S3 buckets with versioning and notifications
│   ├── iam/                        # IAM roles and inline policies
│   ├── codebuild/                  # CodeBuild project for image CI/CD
│   └── agentcore/
│       ├── runtime/                # AgentCore Runtime (agent container host)
│       ├── memory/                 # AgentCore Memory store
│       ├── browser/                # AgentCore Browser tool
│       └── code-interpreter/       # AgentCore Code Interpreter tool
└── src/                            # Agent application source code
```

---

## ✅ Prerequisites

| Tool | Minimum Version | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | v1.3+ | Provision all AWS infrastructure |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2.x | Authentication and manual operations |
| [Docker](https://docs.docker.com/get-docker/) | v20+ | Local image builds and testing |
| [Python](https://www.python.org/downloads/) | v3.9+ | Memory initialization script (`init-memory.py`) |

**Required AWS Permissions:**

Your IAM identity must have permissions covering: Bedrock, ECR, S3, CodeBuild, IAM, CloudWatch, X-Ray, VPC, and Bedrock AgentCore.

> **Bedrock Model Access:** Ensure the foundation model you are targeting (e.g. Claude 3) has access enabled in your AWS account under **Amazon Bedrock → Model Access**.

---

## ⚙️ Configuration

All configurable inputs are declared in `variables.tf`. Key variables:

| Variable | Description | Example |
|---|---|---|
| `stack_name` | Prefix applied to all named resources | `"weather-agent-prod"` |
| `agent_name` | Name of the AgentCore agent | `"weather-agent"` |
| `memory_name` | Name of the AgentCore memory store | `"weather-agent-memory"` |
| `image_tag` | Docker image tag pushed to ECR | `"latest"` or `"v1.2.0"` |
| `network_mode` | AgentCore network mode | `"PUBLIC"` or `"VPC"` |
| `azs` | List of availability zones | `["us-east-1a", "us-east-1b"]` |
| `public_subnets` | CIDR blocks for public subnets | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `private_subnets` | CIDR blocks for private subnets | `["10.0.3.0/24", "10.0.4.0/24"]` |
| `common_tags` | Tags applied to all AgentCore resources | `{ Environment = "prod" }` |

Create a `terraform.tfvars` file to set your values:

```hcl
stack_name   = "weather-agent"
agent_name   = "weather-agent"
memory_name  = "weather-agent-memory"
image_tag    = "latest"
network_mode = "PUBLIC"

azs             = ["us-east-1a", "us-east-1b"]
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

common_tags = {
  Project     = "weather-agent"
  Environment = "production"
  ManagedBy   = "terraform"
}
```

---

## 🚀 Deployment

### 1. Clone the Repository

```bash
git clone https://github.com/<your-org>/weather-agent.git
cd weather-agent
```

### 2. Configure AWS Credentials

```bash
aws configure
# Or using a named profile:
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1
```

### 3. Initialize and Apply Terraform

```bash
# Initialize providers and modules
terraform init

# Review the execution plan
terraform plan -var-file="terraform.tfvars"

# Provision all infrastructure
terraform apply -var-file="terraform.tfvars"
```

> Terraform will automatically:
> - Provision the VPC, ECR, S3 buckets, and IAM roles
> - Wait 30 seconds for IAM propagation before triggering CodeBuild
> - Build and push the agent Docker image to ECR via CodeBuild
> - Deploy the AgentCore Runtime with Browser, Code Interpreter, and Memory tools
> - Seed the Memory store with activity preferences via `init-memory.py`
> - Configure CloudWatch Logs and X-Ray observability

### 4. Verify Deployment

```bash
# Tail live agent application logs
aws logs tail /aws/vendedlogs/bedrock-agentcore/<runtime-id> --follow

# Check artifacts written to the results bucket
aws s3 ls s3://<stack-name>-results-<suffix>/
```

---

## 🧠 AgentCore Memory

The memory store is automatically seeded on first deploy via `scripts/init-memory.py`. It pre-populates the agent with user activity preferences so it can deliver personalised weather recommendations from the very first interaction — no cold start.

To re-initialize memory after modifying the seed data:

```bash
# Force re-trigger the null_resource
terraform apply -replace="null_resource.initialize_memory"
```

---

## 🐳 Docker Image CI/CD

The CodeBuild pipeline is configured as:

- **Build environment:** `amazonlinux2-aarch64-standard:3.0` (ARM64)
- **Compute type:** `BUILD_GENERAL1_LARGE`
- **Source:** Pulled from the agent source S3 bucket
- **Buildspec:** Defined in `scripts/buildspec.yml`
- **Output:** Tagged image pushed to ECR

ECR is configured with:
- **Immutable image tags** — prevents silent overwrites of existing tags
- **Lifecycle policy** — automatically expires images beyond the most recent 5, controlling storage costs

To manually trigger a build:

```bash
aws codebuild start-build \
  --project-name <stack-name>-agent-build \
  --region us-east-1
```

---

## 🔒 Security

| Control | Implementation |
|---|---|
| Least-privilege IAM | Separate scoped roles for AgentCore runtime and CodeBuild — no shared wildcard policies |
| ECR access restriction | Repository policy limits image pulls to the owning AWS account only |
| Immutable image tags | Prevents tag mutation — every deploy references a verifiable, traceable image |
| Network isolation | Agent runs inside a private VPC; NAT gateways handle outbound-only egress |
| No hardcoded credentials | All sensitive values passed via environment variables or resolved at runtime via IAM |
| Workload identity tokens | AgentCore uses scoped workload identity tokens — not long-lived IAM keys |
| Namespace-scoped metrics | CloudWatch `PutMetricData` is restricted to the `bedrock-agentcore` namespace |

---

## 📊 Observability

Full observability is wired up automatically on deploy.

**CloudWatch Logs**
- Log group: `/aws/vendedlogs/bedrock-agentcore/<runtime-id>`
- Retention: 14 days
- Delivery: `APPLICATION_LOGS` via CloudWatch Log Delivery pipeline

**AWS X-Ray**
- Trace delivery type: `TRACES` via X-Ray delivery destination
- Covers: model invocations, tool calls (browser, code interpreter), and memory access

```bash
# Stream live agent logs
aws logs tail /aws/vendedlogs/bedrock-agentcore/<runtime-id> --follow

# View X-Ray traces
open https://console.aws.amazon.com/xray/home
```

---

## 🧹 Teardown

To remove all provisioned resources and stop incurring charges:

```bash
terraform destroy -var-file="terraform.tfvars"
```

> Both S3 buckets and the ECR repository have `force_destroy = true` set, so Terraform will handle emptying and deleting them automatically.

---

## 🛠️ Troubleshooting

**`terraform apply` fails on CodeBuild immediately after IAM creation**
→ The `time_sleep.wait_for_iam` resource waits 30 seconds for IAM propagation. In busy regions this may not be enough — re-run `terraform apply` if CodeBuild fails on the first attempt.

**CodeBuild fails with ECR authentication error**
→ Ensure the CodeBuild role has `ecr:GetAuthorizationToken` on `"*"`. This permission cannot be scoped to a specific repository ARN — it is a global ECR operation.

**AgentCore Memory initialization fails**
→ Verify Python 3 is available in the environment running Terraform. Test manually:
```bash
export MEMORY_ID=<memory-id>
export AWS_REGION=us-east-1
python3 scripts/init-memory.py
```

**Agent returns no weather data**
→ Confirm the Browser tool is active:
```bash
aws bedrock-agentcore get-browser --browser-id <browser-id> --region us-east-1
```

**X-Ray traces not appearing in console**
→ Verify the agent execution role includes all four X-Ray permissions: `PutTraceSegments`, `PutTelemetryRecords`, `GetSamplingRules`, and `GetSamplingTargets`.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Run `terraform fmt` and `terraform validate` before committing
4. Push your branch and open a Pull Request

Please keep module interfaces clean and update `variables.tf` and `outputs.tf` for any new inputs or outputs you introduce.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## 👤 Author

**mmdcloud** — [GitHub Profile](https://github.com/mmdcloud)

---

*If this project helped you, consider giving it a ⭐ on GitHub!*
