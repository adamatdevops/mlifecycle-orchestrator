# =============================================================================
# Zero-Touch ML Deployment Platform - Infrastructure
# =============================================================================
# Terraform configuration for ML inference infrastructure on AWS.
#
# Resources:
# - EKS cluster for inference workloads
# - MLflow tracking server
# - Model registry (S3 + DynamoDB)
# - Observability stack integration
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Remote state configuration (uncomment for production)
  # backend "s3" {
  #   bucket         = "mlifecycle-terraform-state"
  #   key            = "infrastructure/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "mlifecycle-terraform-locks"
  # }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "mlifecycle-orchestrator"
      Environment = var.environment
      ManagedBy   = "terraform"
      Team        = "ml-platform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "production"
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # EKS requirements
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster access - SECURITY: Set public_access to false in production
  cluster_endpoint_public_access  = var.enable_public_endpoint
  cluster_endpoint_private_access = true

  # Managed node groups for inference workloads
  eks_managed_node_groups = {
    # General purpose nodes
    general = {
      name           = "general"
      instance_types = ["m6i.large"]
      min_size       = 1
      max_size       = 5
      desired_size   = 2

      labels = {
        workload = "general"
      }
    }

    # GPU nodes for ML inference (optional)
    inference = {
      name           = "inference"
      instance_types = var.inference_instance_types
      min_size       = 0
      max_size       = var.max_inference_nodes
      desired_size   = var.environment == "production" ? 2 : 1

      labels = {
        workload = "inference"
        gpu      = "true"
      }

      taints = [
        {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  # Cluster add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # IRSA for service accounts
  enable_irsa = true
}

# -----------------------------------------------------------------------------
# Model Registry (S3 + DynamoDB)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "model_registry" {
  bucket = "${var.project_name}-models-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "ML Model Registry"
    Purpose = "Store trained ML models"
  }
}

resource "aws_s3_bucket_versioning" "model_registry" {
  bucket = aws_s3_bucket.model_registry.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_registry" {
  bucket = aws_s3_bucket.model_registry.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "model_registry" {
  bucket = aws_s3_bucket.model_registry.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB for model metadata
resource "aws_dynamodb_table" "model_metadata" {
  name         = "${var.project_name}-model-metadata-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "model_name"
  range_key    = "version"

  attribute {
    name = "model_name"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = false
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name    = "Model Metadata"
    Purpose = "Track deployed model versions"
  }
}

# -----------------------------------------------------------------------------
# MLflow Tracking Server (Optional - for production)
# -----------------------------------------------------------------------------

# ECR repository for MLflow
resource "aws_ecr_repository" "mlflow" {
  count = var.enable_mlflow ? 1 : 0

  name                 = "${var.project_name}/mlflow"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

# MLflow artifacts bucket
resource "aws_s3_bucket" "mlflow_artifacts" {
  count  = var.enable_mlflow ? 1 : 0
  bucket = "${var.project_name}-mlflow-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

# -----------------------------------------------------------------------------
# Inference Service ECR Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "inference_service" {
  name                 = "${var.project_name}/inference-service"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Name    = "Inference Service"
    Purpose = "ML inference container images"
  }
}

resource "aws_ecr_lifecycle_policy" "inference_service" {
  repository = aws_ecr_repository.inference_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IRSA for Inference Service
# -----------------------------------------------------------------------------

module "inference_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-inference-${var.environment}"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["ml-inference:inference-service"]
    }
  }

  role_policy_arns = {
    s3_read = aws_iam_policy.inference_s3_access.arn
  }
}

resource "aws_iam_policy" "inference_s3_access" {
  name        = "${var.project_name}-inference-s3-${var.environment}"
  description = "Allow inference service to read models from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.model_registry.arn,
          "${aws_s3_bucket.model_registry.arn}/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Observability (Prometheus + Grafana via Helm)
# -----------------------------------------------------------------------------

resource "helm_release" "prometheus" {
  count = var.enable_observability ? 1 : 0

  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "55.0.0"

  create_namespace = true

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
        }
      }
      grafana = {
        enabled = true
        adminPassword = var.grafana_admin_password
      }
    })
  ]
}
