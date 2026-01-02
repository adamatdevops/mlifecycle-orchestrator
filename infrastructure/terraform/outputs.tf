# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# -----------------------------------------------------------------------------
# Model Registry
# -----------------------------------------------------------------------------

output "model_registry_bucket" {
  description = "S3 bucket for model artifacts"
  value       = aws_s3_bucket.model_registry.id
}

output "model_registry_bucket_arn" {
  description = "ARN of the model registry bucket"
  value       = aws_s3_bucket.model_registry.arn
}

output "model_metadata_table" {
  description = "DynamoDB table for model metadata"
  value       = aws_dynamodb_table.model_metadata.name
}

# -----------------------------------------------------------------------------
# ECR
# -----------------------------------------------------------------------------

output "inference_service_repository" {
  description = "ECR repository for inference service"
  value       = aws_ecr_repository.inference_service.repository_url
}

output "inference_service_repository_arn" {
  description = "ARN of the inference service ECR repository"
  value       = aws_ecr_repository.inference_service.arn
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

output "inference_service_role_arn" {
  description = "IAM role ARN for inference service"
  value       = module.inference_irsa.iam_role_arn
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# -----------------------------------------------------------------------------
# MLflow (if enabled)
# -----------------------------------------------------------------------------

output "mlflow_artifacts_bucket" {
  description = "S3 bucket for MLflow artifacts"
  value       = var.enable_mlflow ? aws_s3_bucket.mlflow_artifacts[0].id : null
}

output "mlflow_ecr_repository" {
  description = "ECR repository for MLflow"
  value       = var.enable_mlflow ? aws_ecr_repository.mlflow[0].repository_url : null
}
