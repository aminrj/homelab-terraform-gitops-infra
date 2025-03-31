module "kubernetes" {
  source            = "../../modules/kubernetes"
  kubeconfig  = var.kubeconfig
}

module "argocd" {
  source            = "../../modules/argocd"
  kubeconfig  = var.kubeconfig
}

module "metallb" {
  source            = "../../modules/metallb"
  kubeconfig  = var.kubeconfig
}

module "nginx-ingress-controller" {
  source            = "../../modules/nginx-ingress-controller"
  kubeconfig  = var.kubeconfig
}

module "external-dns" {
  source            = "../../modules/external-dns"
  kubeconfig  = var.kubeconfig

  cloudflare_api_token = var.cloudflare_api_token
}

module "cert-manager" {
  source            = "../../modules/cert-manager"
  kubeconfig  = var.kubeconfig
}

module "prometheus-stack" {
  source            = "../../modules/kube-prometheus-stack"
  kubeconfig  = var.kubeconfig
}

module "longhorn" {
  source            = "../../modules/longhorn"
  kubeconfig  = var.kubeconfig
}

# module "metrics_server" {
#   source = "../../modules/metrics-server"
# }
