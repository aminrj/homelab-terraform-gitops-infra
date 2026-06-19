terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
  }
}

# ArgoCD Infrastructure ApplicationSet
resource "kubectl_manifest" "infrastructure_applicationset" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: git@github.com:aminrj/homelab-terraform-gitops-infra.git
        revision: main
        directories:
          - path: infrastructure/*/overlays/prod # Only prod environment
  template:
    metadata:
      name: 'infra-{{path[1]}}-{{path[3]}}' # example: infra-storage-monitoring-prod
    spec:
      project: default
      source:
        repoURL: git@github.com:aminrj/homelab-terraform-gitops-infra.git
        targetRevision: main
        path: 'infrastructure/{{path[1]}}/overlays/{{path[3]}}' # Example: infrastructure/storage-monitoring/overlays/prod
      destination:
        server: https://kubernetes.default.svc
        namespace: 'monitoring' # All infrastructure components go to monitoring namespace
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
YAML

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# ArgoCD Prometheus Safeguards Application
resource "kubectl_manifest" "prometheus_safeguards_application" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-safeguards
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:aminrj/homelab-terraform-gitops-infra.git
    targetRevision: main
    path: infrastructure/prometheus-safeguards
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
YAML

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# --- AI-lab track (HolmesGPT agent + MCP servers) ---
# Bootstrapped here (decision A) since this repo has no app-of-apps that auto-applies
# argocd/*.yaml. Manifests are version-controlled as files and loaded via file().

# AI-lab AppProject (trust boundary) — must exist before the ApplicationSet/Application.
resource "kubectl_manifest" "ai_lab_appproject" {
  yaml_body = file("${path.module}/../../argocd/ai-lab-appproject.yaml")

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# AI-lab ApplicationSet (discovers ai-lab/*/overlays/prod).
resource "kubectl_manifest" "ai_lab_applicationset" {
  yaml_body = file("${path.module}/../../argocd/ai-lab-applicationset.yaml")

  depends_on = [
    kubectl_manifest.ai_lab_appproject
  ]
}

# HolmesGPT Helm chart Application (standalone, decision B option 1).
resource "kubectl_manifest" "ai_lab_holmes_application" {
  yaml_body = file("${path.module}/../../argocd/ai-lab-holmes-application.yaml")

  depends_on = [
    kubectl_manifest.ai_lab_appproject
  ]
}

# Ensure ArgoCD namespace exists
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }
}

# Ensure monitoring namespace exists
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }
}
