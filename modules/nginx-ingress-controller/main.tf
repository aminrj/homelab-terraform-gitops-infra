# module "nginx-controller" {
#   source  = "terraform-iaac/nginx-controller/helm"
#   version = "2.3.0"
#   wait    = false
#
#   # values = [file("${path.module}/values.yaml")]
#   ip_address= "10.0.30.200"
#   metrics_enabled= true
#
# }

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  version    = "4.12.0" # or the latest stable
  namespace  = "ingress-nginx"
  create_namespace = true
  wait = false

  values = [file("${path.module}/values.yaml")]

}
