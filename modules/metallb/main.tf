# resource "helm_release" "metallb" {
#   name       = "metallb"
#   chart      = "metallb"
#   repository = "https://metallb.github.io/metallb"
#   version    = "0.14.9"
#   namespace  = "metallb-system"
#
#   create_namespace = true
# }
#
# resource "terraform_data" "metallb_configs" {
#
#   depends_on = [
#     helm_release.metallb
#   ]
#
#   input = templatefile("${path.module}/metallb-config.yaml.tpl", {
#     address_range = var.metallb_address_range
#   })
#
#   provisioner "local-exec" {
#     command     = "echo '${self.input}' | kubectl apply -f -"
#     interpreter = ["/bin/bash", "-c"]
#   }
#
# }

# metallb/main.tf
resource "helm_release" "metallb" {
  name             = "metallb"
  chart            = "metallb"
  repository       = "https://metallb.github.io/metallb"
  version          = "0.14.9"
  namespace        = "metallb-system"
  create_namespace = true
  wait             = true
}

resource "kubernetes_manifest" "metallb_ipaddresspool" {
  depends_on = [helm_release.metallb]
  
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "lb-addresses"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.metallb_address_range]
    }
  }
}

resource "kubernetes_manifest" "metallb_l2advertisement" {
  depends_on = [kubernetes_manifest.metallb_ipaddresspool]
  
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "lb-addresses"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["lb-addresses"]
    }
  }
}
