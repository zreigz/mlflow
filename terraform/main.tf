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

locals {
  # fileexists() never throws — safe to use as an in-cluster guard.
  in_cluster = fileexists("/var/run/secrets/kubernetes.io/serviceaccount/token")
}

provider "kubernetes" {
  # In-cluster: use the service-account token and CA cert mounted by Kubernetes.
  # Locally (e.g. Docker / dev): use the kubeconfig file.
  # Setting any of host/token/ca explicitly to a non-null value causes the
  # provider to skip kubeconfig auto-detection, so config_path must be set
  # explicitly when running outside a pod.
  host                   = local.in_cluster ? "https://kubernetes.default.svc" : null
  cluster_ca_certificate = local.in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt") : null
  token                  = local.in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/token") : null
  config_path            = local.in_cluster ? null : pathexpand("~/.kube/config")
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

# ── Flask server secret key (required by the chart; bypasses the Helm hook) ───
# The chart deployment mounts this secret as MLFLOW_FLASK_SERVER_SECRET_KEY.
# Secret name is hard-coded in the chart as <release>-flask-server-secret-key.

resource "kubernetes_manifest" "flask_secret" {
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = "mlflow-flask-server-secret-key"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "mlflow"
      }
    }
    data = {
      MLFLOW_FLASK_SERVER_SECRET_KEY = base64encode(random_password.mlflow_secret_key.result)
    }
  }

  field_manager {
    force_conflicts = true
  }
}
