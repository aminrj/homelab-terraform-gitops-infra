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
        repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
        revision: main
        directories:
          - path: infrastructure/*/overlays/prod # Only prod environment
  template:
    metadata:
      name: 'infra-{{path[1]}}-{{path[3]}}' # example: infra-storage-monitoring-prod
    spec:
      project: default
      source:
        repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
        targetRevision: main
        path: 'infrastructure/{{path[1]}}/overlays/{{path[3]}}' # Example: infrastructure/storage-monitoring/overlays/prod
      destination:
        server: https://kubernetes.default.svc
        namespace: 'monitoring' # All infrastructure components go to monitoring namespace
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
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
    repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
    targetRevision: main
    path: infrastructure/prometheus-safeguards
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
YAML

  depends_on = [
    kubernetes_namespace.argocd
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