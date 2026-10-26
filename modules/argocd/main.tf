
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
  }
}

resource "kubectl_manifest" "argocd_self_managed" {
  depends_on = [helm_release.argocd]
  # yaml_body = file("${path.module}/argocd-config.yaml")

  yaml_body = templatefile("${path.module}/argocd-config.yaml", {
    TARGET_SERVER = var.target_cluster_server
  })
}

# Install ArgoCD with Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = var.argocd_namespace
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "7.9.1" # Argo CD 2.14.11; step 1 of 2.8 -> 3.5 (step 2: chart 10.x)

  create_namespace = true

  values = [file("${path.module}/values.yaml")]

  # Admin password from Key Vault (modules/admin-passwords); only the hash reaches the cluster.
  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.admin_password_bcrypt
  }
  set {
    name  = "configs.secret.argocdServerAdminPasswordMtime"
    value = var.admin_password_mtime
  }

  wait = false
}

# # Deploy ArgoCD Self-Managed Application (Points to GitOps Repo)
# resource "kubectl_manifest" "argocd_self_managed" {
#   depends_on = [helm_release.argocd]
#
#   yaml_body = file("${path.module}/argocd-config.yaml")
# }

# # Configmap to register the repo inside ArgoCD
# resource "kubectl_manifest" "argocd_gitops_repo_config" {
#   depends_on = [helm_release.argocd]
#
#   yaml_body = file("${path.module}/repository-cm.yaml")
# }

# Deploy Applications & ApplicationSets from GitOps Repo
# resource "kubectl_manifest" "argocd_applications" {
#   depends_on = [kubectl_manifest.argocd_self_managed] 
#
#   for_each = fileset("${path.root}/argocd", "*.yaml")
#
#   yaml_body = file("${path.root}/argocd/${each.value}")
# }

# ArgoCD's first-boot password stops working once the managed one is set; its secret goes.
resource "terraform_data" "drop_initial_admin_secret" {
  triggers_replace = [var.admin_password_mtime]
  depends_on       = [helm_release.argocd]

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${pathexpand(var.kubeconfig)} --context ${var.kube_context} -n ${var.argocd_namespace} delete secret argocd-initial-admin-secret --ignore-not-found"
  }
}
