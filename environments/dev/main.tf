module "kubernetes" {
  source            = "../../modules/kubernetes"
}

module "argocd" {
  source            = "../../modules/argocd"
}

module "metallb" {
  source            = "../../modules/metallb"
}

module "nginx-ingress-controller" {
  source            = "../../modules/nginx-ingress-controller"
}

module "external-dns" {
  source            = "../../modules/external-dns"
}

module "cert-manager" {
  source            = "../../modules/cert-manager"
}
