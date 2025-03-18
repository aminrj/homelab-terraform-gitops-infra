module "nginx-controller" {
  source  = "terraform-iaac/nginx-controller/helm"
  version = "2.3.0"
  wait    = false

  # values = [file("${path.module}/values.yaml")]
  ip_address= "10.0.30.200"
  metrics_enabled= true
}
