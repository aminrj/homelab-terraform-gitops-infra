module "kubernetes" {
  source            = "../../modules/kubernetes"
  kubeconfig  = var.kubeconfig
}

module "metallb" {
  source            = "../../modules/metallb"
  kubeconfig  = var.kubeconfig
  metallb_address_range = var.metallb_address_range
}

module "nginx-ingress-controller" {
  source            = "../../modules/nginx-ingress-controller"
  kubeconfig  = var.kubeconfig
}

module "argocd" {
  source            = "../../modules/argocd"
  kubeconfig  = var.kubeconfig
  target_cluster_server = var.target_cluster_server

}

module "longhorn" {
  source            = "../../modules/longhorn"
  kubeconfig  = var.kubeconfig
  default_data_path = var.default_data_path
  kubelet_root_dir = var.kubelet_root_dir
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
  storage_class = var.storage_class
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
  pg_instance_count     = 1
  pg_storage_class      = "longhorn"
  pg_storage_size       = "50Gi"
  pg_superuser_secret   = "pg-superuser-qa"
  pg_app_secret         = "pg-app-qa"
  pg_monitoring_enabled = true
}

