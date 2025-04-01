resource "helm_release" "metallb" {
  name       = "metallb"
  chart      = "metallb"
  repository = "https://metallb.github.io/metallb"
  version    = "0.14.9"
  namespace  = "metallb-system"

  create_namespace = true
}

resource "terraform_data" "metallb_configs" {

  input = templatefile("${path.module}/metallb-config.yaml.tpl", {
    address_range = var.metallb_address_range
  })

  provisioner "local-exec" {
    command     = "echo '${self.input}' | kubectl apply -f -"
    interpreter = ["/bin/bash", "-c"]
  }
}

