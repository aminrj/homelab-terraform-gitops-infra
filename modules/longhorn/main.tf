# resource "helm_release" "longhorn" {
#   name       = "longhorn"
#   repository = "https://charts.longhorn.io"
#   chart      = "longhorn"
#   namespace  = "longhorn-system"
#
#   create_namespace = true
#
#   values = [file("${path.module}/values.yaml")]
#
#   wait = false
#
# }
#

resource "helm_release" "longhorn" {
  name       = "longhorn"
  chart      = "longhorn"
  repository = "https://charts.longhorn.io"
  version    = "1.5.1"
  namespace  = "longhorn-system"

  create_namespace = true

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      default_data_path    = var.default_data_path
      default_replica_count = var.default_replica_count
      kubelet_root_dir     = var.kubelet_root_dir
      ui_service_type      = var.ui_service_type
    })
  ]
}
