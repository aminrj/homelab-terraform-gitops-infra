
# Install ArgoCD with Helm
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

# Deploy ArgoCD Self-Managed Application (Points to GitOps Repo)
resource "kubectl_manifest" "argocd_self_managed" {
  depends_on = [helm_release.argocd]

  yaml_body = file("${path.module}/argocd-config.yaml")
}

# Configmap to register the repo inside ArgoCD
resource "kubectl_manifest" "argocd_gitops_repo_config" {
  depends_on = [helm_release.argocd]

  yaml_body = file("${path.module}/repository-cm.yaml")
}

# Deploy Applications & ApplicationSets from GitOps Repo
resource "kubectl_manifest" "argocd_applications" {
  depends_on = [kubectl_manifest.argocd_self_managed] 

  for_each = fileset("${path.root}/argocd", "*.yaml")

  yaml_body = file("${path.root}/argocd/${each.value}")
}
