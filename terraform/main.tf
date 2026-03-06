data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ---------------------------------------------------------------------
# VPC Configuration
# ---------------------------------------------------------------------
module "vpc" {
  source                  = "./modules/vpc"
  vpc_name                = "vpc"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  database_subnets        = []
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  tags = {
    Project = "weather-agent"
  }
}

# ---------------------------------------------------------------------
# ECR Configuration
# ---------------------------------------------------------------------
module "container_registry" {
  source               = "./modules/ecr"
  force_delete         = true
  scan_on_push         = false
  image_tag_mutability = "IMMUTABLE"
  bash_command         = "bash ${path.cwd}/scripts/build-image.sh"
  name                 = "container-registry"
  repository_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPullFromAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.id}:root"
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
      }
    ]
  })
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------
# Memory Initialization - Populate Memory with Activity Preferences
# ---------------------------------------------------------------------
resource "null_resource" "initialize_memory" {
  triggers = {
    memory_id = module.agentcore_memory.id
    region    = data.aws_region.current.id
  }

  provisioner "local-exec" {
    command     = "python3 ${path.module}/scripts/init-memory.py"
    working_dir = path.module

    environment = {
      MEMORY_ID  = module.agentcore_memory.id
      AWS_REGION = data.aws_region.current.id
    }
  }

  depends_on = [
    module.agentcore_memory
  ]
}

# ---------------------------------------------------------------------
# Wait for IAM propagation before triggering build
# ---------------------------------------------------------------------
resource "time_sleep" "wait_for_iam" {
  depends_on = [
    module.codebuild_role,
    module.agent_execution_role
  ]

  create_duration = "30s"
}

# ---------------------------------------------------------------------
# S3 Configuration
# ---------------------------------------------------------------------
module "agent_source_bucket" {
  source      = "./modules/s3"
  bucket_name = "${var.stack_name}-agent-source-"
  objects = [
    {
      key    = "./files/code.zip"
      source = "code.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name    = "${var.stack_name}-agent-source"
    Purpose = "Store Weather Agent source code for CodeBuild"
  }
}

module "agent_results_bucket" {
  source             = "./modules/s3"
  bucket_name        = "${var.stack_name}-results-"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name    = "${var.stack_name}-results"
    Purpose = "Store Weather Agent generated artifacts"
  }
}

module "codebuild_cache_bucket" {
  source             = "./modules/s3"
  bucket_name        = "codebuild-cache-bucket"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name = "codebuild-cache-bucket"
  }
}


# ---------------------------------------------------------------------
# IAM Configuration
# ---------------------------------------------------------------------
module "agent_execution_role" {
  source             = "./modules/iam"
  role_name          = "agent-execution-role"
  role_description   = "IAM role for agent execution"
  policy_name        = "agent-execution-role-policy"
  policy_description = "IAM policy for agent execution"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "bedrock-agentcore.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": "AssumeRolePolicy"
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
              Sid    : "ECRImageAccess"
              Effect : "Allow"
              Action : [
                "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchCheckLayerAvailability"
              ]
              Resource : "${module.container_registry.arn}"
            },
            {
              Sid      : "ECRTokenAccess"
              Effect   : "Allow"
              Action   : ["ecr:GetAuthorizationToken"]
              Resource : "*"
            },
            {
              Sid    : "CloudWatchLogs"
              Effect : "Allow"
              Action : [
                "logs:DescribeLogStreams",
                "logs:CreateLogGroup",
                "logs:DescribeLogGroups",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
              ]
              Resource : "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.id}:log-group:/aws/bedrock-agentcore/runtimes/*"
            },
            {
              Sid    : "XRayTracing"
              Effect : "Allow"
              Action : [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords",
                "xray:GetSamplingRules",
                "xray:GetSamplingTargets"
              ]
              Resource : "*"
            },
            {
              Sid      : "CloudWatchMetrics"
              Effect   : "Allow"
              Action   : ["cloudwatch:PutMetricData"]
              Resource : "*"
              Condition = {
                StringEquals = {
                  "cloudwatch:namespace" = "bedrock-agentcore"
                }
              }
            },
            {
              Sid    : "BedrockModelInvocation"
              Effect : "Allow"
              Action : [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
              ]
              Resource : "*"
            },
            {
              Sid    : "GetAgentAccessToken"
              Effect : "Allow"
              Action : [
                "bedrock-agentcore:GetWorkloadAccessToken",
                "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
                "bedrock-agentcore:GetWorkloadAccessTokenForUserId"
              ]
              Resource : [
                "arn:aws:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.id}:workload-identity-directory/default",
                "arn:aws:bedrock-agentcore:${data.aws_region.current.id}:${data.aws_caller_identity.current.id}:workload-identity-directory/default/workload-identity/*"
              ]
            },
            {
              Sid    : "S3ResultsAccess"
              Effect : "Allow"
              Action : [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
              ]
              Resource : [
                "${module.agent_results_bucket.arn}",
                "${module.agent_results_bucket.arn}/*"
              ]
            }
        ]
    }
    EOF
}

resource "aws_iam_role_policy_attachment" "agent_execution_managed" {
  role       = module.agent_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/BedrockAgentCoreFullAccess"
}

module "codebuild_role" {
  source             = "./modules/iam"
  role_name          = "codebuild-role"
  role_description   = "IAM role for CodeBuild"
  policy_name        = "codebuild-role-policy"
  policy_description = "IAM policy for CodeBuild"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "codebuild.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": "AssumeRolePolicy"
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
              Sid    : "CloudWatchLogs"
              Effect : "Allow"
              Action : [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
              ]
              Resource : "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.id}:log-group:/aws/codebuild/*"
            },
            # ECR Access
            {
              Sid    : "ECRAccess"
              Effect : "Allow"
              Action : [
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:GetAuthorizationToken",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload"
              ]
              Resource : [
                "${module.container_registry.arn}",
                "*"
              ]
            },
            # S3 Source Access
            {
              Sid    : "S3SourceAccess"
              Effect : "Allow"
              Action : [
                "s3:GetObject",
                "s3:GetObjectVersion"
              ]
              Resource : "${module.agent_source_bucket.arn}/*"
            },
            {
              Sid    : "S3BucketAccess"
              Effect : "Allow"
              Action : [
                "s3:ListBucket",
                "s3:GetBucketLocation"
              ]
              Resource : "${module.agent_source_bucket.arn}"
            }
        ]
    }
    EOF
}

# ---------------------------------------------------------------------
# CodeBuild Configuration
# ---------------------------------------------------------------------
module "codebuild" {
  source                        = "./modules/codebuild"
  build_timeout                 = 60
  cache_bucket_name             = module.codebuild_cache_bucket.bucket
  cloudwatch_group_name         = "/aws/codebuild/${var.stack_name}-agent-build"
  cloudwatch_stream_name        = "carshub-codebuiild-frontend-stream"
  codebuild_project_description = "Build Weather Agent Docker image for ${var.stack_name}"
  codebuild_project_name        = "${var.stack_name}-agent-build"
  role                          = module.codebuild_role.arn
  compute_type                  = "BUILD_GENERAL1_LARGE"
  env_image                     = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
  env_type                      = "ARM_CONTAINER"
  fetch_submodules              = true
  force_destroy_cache_bucket    = true
  image_pull_credentials_type   = "CODEBUILD"
  privileged_mode               = true
  source_type                   = "S3"
  source_location               = "${module.agent_source_bucket.id}/${module.agent_source_bucket.objects[0].key}"
  buildspec                     = file("${path.module}/scripts/buildspec.yaml")
  source_version                = "frontend"
  environment_variables = [
    {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.id
    },
    {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.id
    },
    {
      name  = "IMAGE_REPO_NAME"
      value = module.container_registry.name
    },
    {
      name  = "IMAGE_TAG"
      value = var.image_tag
    },
    {
      name  = "STACK_NAME"
      value = var.stack_name
    },
    {
      name  = "AGENT_NAME"
      value = "weather-agent"
    }
  ]
  tags = {
    Name   = "${var.stack_name}-agent-build"
    Module = "CodeBuild"
    Agent  = "WeatherAgent"
  }
  depends_on = [
    module.codebuild_role
  ]
}

# ---------------------------------------------------------------------
# Bedrock Agentcore Configuration
# ---------------------------------------------------------------------
module "agentcore_browser" {
  source       = "./modules/agentcore/browser"
  stack_name   = var.stack_name
  network_mode = var.network_mode
  common_tags  = var.common_tags
}

module "agentcore_code_interpreter" {
  source       = "./modules/agentcore/code-interpreter"
  stack_name   = var.stack_name
  network_mode = var.network_mode
  common_tags  = var.common_tags
}

module "agentcore_memory" {
  source       = "./modules/agentcore/memory"
  stack_name   = var.stack_name
  memory_name  = var.memory_name
  network_mode = var.network_mode
  common_tags  = var.common_tags
}

module "agentcore_runtime" {
  source        = "./modules/agentcore/runtime"
  stack_name    = var.stack_name
  agent_name    = var.agent_name
  container_uri = "${module.container_registry.repository_url}:${var.image_tag}"
  role_arn      = module.agent_execution_role.arn
  network_mode  = var.network_mode
  environment_variables = {
    AWS_REGION          = data.aws_region.current.id
    AWS_DEFAULT_REGION  = data.aws_region.current.id
    RESULTS_BUCKET      = module.agent_results_bucket.id
    BROWSER_ID          = module.agentcore_browser.browser_id
    CODE_INTERPRETER_ID = module.agentcore_code_interpreter.code_interpreter_id
    MEMORY_ID           = module.agentcore_memory.id
  }
  tags = {
    Name        = "${var.stack_name}-agent-runtime"
    Environment = "production"
    Module      = "BedrockAgentCore"
    Agent       = "WeatherAgent"
  }
}

# ---------------------------------------------------------------------
# Observability Module - CloudWatch Logs and X-Ray Traces Delivery
# ---------------------------------------------------------------------

# CloudWatch Log Group for vended log delivery
resource "aws_cloudwatch_log_group" "agent_runtime_logs" {
  name              = "/aws/vendedlogs/bedrock-agentcore/${module.agentcore_runtime.id}"
  retention_in_days = 14

  tags = {
    Name    = "${var.stack_name}-agent-logs"
    Purpose = "Agent runtime application logs"
    Module  = "Observability"
  }

  depends_on = [module.agentcore_runtime]
}

# Delivery Source for Application Logs
resource "aws_cloudwatch_log_delivery_source" "logs" {
  name         = "${module.agentcore_runtime.id}-logs-source"
  log_type     = "APPLICATION_LOGS"
  resource_arn = module.agentcore_runtime.arn

  depends_on = [module.agentcore_runtime]
}

# Delivery Destination for Logs (CloudWatch Logs)
resource "aws_cloudwatch_log_delivery_destination" "logs" {
  name = "${module.agentcore_runtime.id}-logs-destination"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.agent_runtime_logs.arn
  }

  tags = {
    Name    = "${var.stack_name}-logs-destination"
    Purpose = "CloudWatch Logs delivery destination"
    Module  = "Observability"
  }

  depends_on = [aws_cloudwatch_log_group.agent_runtime_logs]
}

# Delivery Connection for Logs
resource "aws_cloudwatch_log_delivery" "logs" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.logs.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.logs.arn

  tags = {
    Name    = "${var.stack_name}-logs-delivery"
    Purpose = "Connect logs source to CloudWatch destination"
    Module  = "Observability"
  }

  depends_on = [
    aws_cloudwatch_log_delivery_source.logs,
    aws_cloudwatch_log_delivery_destination.logs
  ]
}

# ---------------------------------------------------------------------
# X-Ray Traces Setup
# ---------------------------------------------------------------------
resource "aws_cloudwatch_log_delivery_source" "traces" {
  name         = "${module.agentcore_runtime.id}-traces-source"
  log_type     = "TRACES"
  resource_arn = module.agentcore_runtime.arn

  depends_on = [module.agentcore_runtime]
}

resource "aws_cloudwatch_log_delivery_destination" "traces" {
  name                      = "${module.agentcore_runtime.id}-traces-destination"
  delivery_destination_type = "XRAY"

  tags = {
    Name    = "${var.stack_name}-traces-destination"
    Purpose = "X-Ray traces delivery destination"
    Module  = "Observability"
  }
}

resource "aws_cloudwatch_log_delivery" "traces" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.traces.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.traces.arn

  tags = {
    Name    = "${var.stack_name}-traces-delivery"
    Purpose = "Connect traces source to X-Ray destination"
    Module  = "Observability"
  }

  depends_on = [
    aws_cloudwatch_log_delivery_source.traces,
    aws_cloudwatch_log_delivery_destination.traces
  ]
}