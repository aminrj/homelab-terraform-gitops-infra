resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = var.argocd_namespace
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "5.46.0"

  create_namespace = true

  values = [file("${path.module}/values.yaml")]
 
  # Helm release drift fix (Terraform keeps trying to update it)
  set {
      name  = "installCRDs"
      value = "true"
    }

  timeout = 600  # Increase timeout
  force_update = true  # Forces update in case of drift
  cleanup_on_fail = true  # Ensures Helm deletes failed installs

  lifecycle {
    ignore_changes = [version]
  }
}

