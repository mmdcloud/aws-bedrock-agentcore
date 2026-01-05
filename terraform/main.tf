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
  database_subnets        = var.database_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  tags = {
    Project = "text-to-sql"
  }
}

module "frontend_lb_sg" {
  source = "./modules/security-groups"
  name   = "frontend-lb-sg"
  vpc_id = module.vpc.vpc_id
  ingress_rules = [
    {
      description     = "HTTP Traffic"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
    },
    {
      description     = "HTTPS Traffic"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
    }
  ]
  egress_rules = [
    {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name = "frontend-lb-sg"
  }
}

module "ecs_frontend_sg" {
  source = "./modules/security-groups"
  name   = "ecs-frontend-sg"
  vpc_id = module.vpc.vpc_id
  ingress_rules = [
    {
      from_port       = 3000
      to_port         = 3000
      protocol        = "tcp"
      cidr_blocks     = []
      security_groups = [module.frontend_lb_sg.id]
    }
  ]
  egress_rules = [
    {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name = "ecs-frontend-sg"
  }
}

module "frontend_lb_logs" {
  source        = "./modules/s3"
  bucket_name   = "frontend-lb-logs"
  objects       = []
  bucket_policy = ""
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
  versioning_enabled = "Enabled"
  force_destroy      = true
}

module "frontend_container_registry" {
  source               = "./modules/ecr"
  force_delete         = true
  scan_on_push         = false
  image_tag_mutability = "IMMUTABLE"
  bash_command         = "bash ${path.cwd}/../src/frontend/artifact_push.sh frontend-td ${var.region} http://${module.backend_lb.dns_name}"
  name                 = "frontend-td"
}

module "frontend_lb" {
  source                     = "terraform-aws-modules/alb/aws"
  name                       = "frontend-lb"
  load_balancer_type         = "application"
  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets
  enable_deletion_protection = false
  drop_invalid_header_fields = true
  ip_address_type            = "ipv4"
  internal                   = false
  security_groups = [
    module.frontend_lb_sg.id
  ]
  access_logs = {
    bucket = "${module.frontend_lb_logs.bucket}"
  }
  listeners = {
    frontend_lb_http_listener = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "frontend_lb_target_group"
      }
    }
  }
  target_groups = {
    frontend_lb_target_group = {
      backend_protocol = "HTTP"
      backend_port     = 3000
      target_type      = "ip"
      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 30
        path                = "/auth/signin"
        port                = 3000
        protocol            = "HTTP"
        unhealthy_threshold = 3
      }
      create_attachment = false
    }
  }
  tags = {
    Project = "text-to-sql-frontend-lb"
  }
}

module "ecs_task_execution_role" {
  source             = "../../../modules/iam"
  role_name          = "ecs-task-execution-role"
  role_description   = "IAM role for ECS task execution"
  policy_name        = "ecs-task-execution-policy"
  policy_description = "IAM policy for ECS task execution"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "ecs-tasks.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "s3:PutObject"
                ],
                "Resource": "*",
                "Effect": "Allow"
            },
            {
              "Effect": "Allow",
              "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
              ],
              "Resource": [
                "${module.db_credentials.arn}",
                "${module.pinecone_api_key.arn}"
              ]
            },
            {
                "Action": [
                  "bedrock:InvokeAgent",
                  "bedrock:InvokeModel"
                ],
                "Resource": "*",
                "Effect": "Allow"
            },
        ]
    }
    EOF
}

# ECR-ECS policy attachment 
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = module.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

module "frontend_ecs_log_group" {
  source            = "./modules/cloudwatch/cloudwatch-log-group"
  log_group_name    = "/aws/ecs/frontend-ecs"
  retention_in_days = 90
}

module "backend_ecs_log_group" {
  source            = "./modules/cloudwatch/cloudwatch-log-group"
  log_group_name    = "/aws/ecs/backend-ecs"
  retention_in_days = 90
}

module "ecs" {
  source       = "terraform-aws-modules/ecs/aws"
  cluster_name = "text-to-sql-cluster"
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 100
      base   = 1
    }
  }
  services = {
    ecs-frontend = {
      cpu                    = 2048
      memory                 = 4096
      task_exec_iam_role_arn = module.ecs_task_execution_role.arn
      iam_role_arn           = module.ecs_task_execution_role.arn
      desired_count          = 2
      assign_public_ip       = false
      deployment_controller = {
        type = "ECS"
      }
      network_mode = "awsvpc"
      runtime_platform = {
        cpu_architecture        = "X86_64"
        operating_system_family = "LINUX"
      }
      launch_type              = "FARGATE"
      scheduling_strategy      = "REPLICA"
      requires_compatibilities = ["FARGATE"]
      container_definitions = {
        ecs-frontend = {
          cpu       = 1024
          memory    = 2048
          essential = true
          image     = "${module.frontend_container_registry.repository_url}:latest"          
          healthCheck = {
            command = ["CMD-SHELL", "curl -f http://localhost:3000/auth/signin || exit 1"]
          }
          ulimits = [
            {
              name      = "nofile"
              softLimit = 65536
              hardLimit = 65536
            }
          ]
          portMappings = [
            {
              name          = "ecs-frontend"
              containerPort = 3000
              hostPort      = 3000
              protocol      = "tcp"
            }
          ]
          environment = [
            {
              name  = "BASE_URL"
              value = "${module.backend_lb.dns_name}"
            }
          ]
          capacity_provider_strategy = {
            ASG = {
              base              = 20
              capacity_provider = "ASG"
              weight            = 50
            }
          }
          readonlyRootFilesystem    = false
          enable_cloudwatch_logging = false
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = module.frontend_ecs_log_group.name
              awslogs-region        = var.region
              awslogs-stream-prefix = "frontend"
            }
          }
          memoryReservation = 100
          restartPolicy = {
            enabled              = true
            ignoredExitCodes     = [1]
            restartAttemptPeriod = 60
          }
        }
      }
      load_balancer = {
        service = {
          target_group_arn = module.frontend_lb.target_groups["frontend_lb_target_group"].arn
          container_name   = "ecs-frontend"
          container_port   = 3000
        }
      }
      subnet_ids                    = module.vpc.private_subnets
      vpc_id                        = module.vpc.vpc_id
      security_group_ids            = [module.ecs_frontend_sg.id]
      availability_zone_rebalancing = "ENABLED"
    }    
  }
}