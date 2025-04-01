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

module "cnpg_operator" {
  source = "../../modules/cnpg-operator"
  use_longhorn_storage = true
  namespace = "cnpg-qa"
  kubeconfig  = var.kubeconfig
}

module "cnpg_cluster" {
  source = "../../modules/cnpg-cluster"

  namespace             = "cnpg-qa"
  pg_cluster_name       = "pg-qa"
  pg_instance_count     = 3
  pg_storage_class      = "longhorn"
  pg_storage_size       = "50Gi"
  pg_superuser_secret   = "pg-superuser-qa"
  pg_app_secret         = "pg-app-qa"
  pg_monitoring_enabled = true
}

# module "metrics_server" {
#   source = "../../modules/metrics-server"
# }
