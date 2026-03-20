terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "kubernetes" {
  # Explicit in-cluster configuration: reads the service-account token and CA
  # cert that Kubernetes mounts into every pod automatically.
  host                   = "https://kubernetes.default.svc"
  cluster_ca_certificate = file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
  token                  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")
}

# ── Random secrets ────────────────────────────────────────────────────────────

resource "random_password" "mlflow_secret_key" {
  length  = 32
  special = false
}

# ── Namespace ─────────────────────────────────────────────────────────────────
# The namespace is created by Plural's ServiceDeployment (createNamespace: true).
# Terraform only reads it to confirm secrets are placed in the correct namespace.

data "kubernetes_namespace" "mlflow" {
  metadata {
    name = var.namespace
  }
}

# ── MLflow secrets ────────────────────────────────────────────────────────────
# kubernetes_manifest uses server-side apply (upsert) so re-runs never fail
# with "already exists", even when Terraform state is reset.

resource "kubernetes_manifest" "mlflow" {
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = "mlflow-secrets"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "mlflow"
      }
    }
    # data values must be base64-encoded (kubernetes_manifest sends the manifest verbatim)
    data = {
      # Secret key used by MLflow for token signing / CSRF protection
      secret-key = base64encode(random_password.mlflow_secret_key.result)
      # Backend store URI – matches backendStore.postgres.* in helm/mlflow.yaml
      backend-store-uri = base64encode("postgresql+psycopg2://mlflow:mlflow@mlflow-postgresql:5432/mlflow")
    }
  }

  field_manager {
    force_conflicts = true
  }
}

