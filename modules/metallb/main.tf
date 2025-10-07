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

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

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

# Wait for MetalLB CRDs to be installed
resource "time_sleep" "wait_for_metallb_crds" {
  depends_on = [helm_release.metallb]
  create_duration = "60s"
}

# Use kubectl provider for CRD-dependent resources
resource "kubectl_manifest" "metallb_ipaddresspool" {
  depends_on = [time_sleep.wait_for_metallb_crds]
  
  validate_schema    = false
  server_side_apply  = true
  wait_for_rollout   = true
  
  yaml_body = <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lb-addresses
  namespace: metallb-system
spec:
  addresses:
  - ${var.metallb_address_range}
YAML
}

resource "kubectl_manifest" "metallb_l2advertisement" {
  depends_on = [kubectl_manifest.metallb_ipaddresspool]
  
  validate_schema    = false
  server_side_apply  = true
  wait_for_rollout   = true
  
  yaml_body = <<YAML
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lb-addresses
  namespace: metallb-system
spec:
  ipAddressPools:
  - lb-addresses
YAML
}
