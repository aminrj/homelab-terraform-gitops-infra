resource "helm_release" "metallb" {
  name       = "metallb"
  chart      = "metallb"
  repository = "https://metallb.github.io/metallb"
  version    = "0.14.9"
  namespace  = "metallb-system"

  create_namespace = true
  wait             = false
}

resource "terraform_data" "metallb_configs" {
  depends_on = [helm_release.metallb]
  input      = file("${path.module}/metallb-config.yaml")

  provisioner "local-exec" {
    command     = "echo '${self.input}' | kubectl apply -f -"
    interpreter = ["/bin/bash", "-c"]
  }
  provisioner "local-exec" {
    when        = destroy
    command     = "echo '${self.input}' | kubectl delete -f -"
    interpreter = ["/bin/bash", "-c"]
  }
}
