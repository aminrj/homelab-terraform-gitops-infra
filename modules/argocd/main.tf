resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = var.argocd_namespace
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "5.46.0"

  create_namespace = true

  values = [file("${path.module}/values.yaml")]
 
  wait    = false
}

resource "kubectl_manifest" "argocd_self_managed" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-config
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:aminrj.com/terraform-gitops-infra.git
    targetRevision: main
    path: argocd
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
}
