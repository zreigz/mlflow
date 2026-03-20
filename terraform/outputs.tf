output "namespace" {
  description = "MLflow namespace"
  value       = var.namespace
}

output "mlflow_secret_name" {
  description = "Name of the Kubernetes secret containing MLflow credentials"
  value       = kubernetes_manifest.mlflow.manifest.metadata.name
}

output "secret_key" {
  description = "MLflow secret key (sensitive)"
  value       = random_password.mlflow_secret_key.result
  sensitive   = true
}

