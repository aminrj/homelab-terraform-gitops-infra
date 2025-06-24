
resource "helm_release" "longhorn" {
  name             = "longhorn"
  chart            = "longhorn"
  repository       = "https://charts.longhorn.io"
  version          = "1.8.2"
  namespace        = "longhorn-system"
  create_namespace = true

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      default_data_path      = var.default_data_path
      default_replica_count  = var.default_replica_count
      kubelet_root_dir       = var.kubelet_root_dir
      ui_service_type        = var.ui_service_type
    })
  ]
}

# Ensure nodes are properly labeled for Longhorn
resource "null_resource" "prepare_longhorn_nodes" {
  depends_on = [helm_release.longhorn]
  
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for Longhorn to be ready
      kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
      
      # Label nodes for Longhorn (if not already done)
      kubectl label nodes --all node.longhorn.io/create-default-disk=true --overwrite
    EOT
  }
}

