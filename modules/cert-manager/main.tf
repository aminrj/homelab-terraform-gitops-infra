# make sure to install microk8s cert-manager plugin before

# Now that the CRDs and the controller are definitely in place...
resource "kubernetes_manifest" "letsencrypt_staging" {
  # depends_on = [helm_release.cert_manager_app]
  # depends_on = [null_resource.wait_for_cert_manager_ready]

  manifest = yamldecode(file("${path.module}/issuers/letsencrypt-staging.yaml"))
}

resource "kubernetes_manifest" "letsencrypt_prod" {
  # depends_on = [helm_release.cert_manager_app]
  # depends_on = [null_resource.wait_for_cert_manager_ready]
  manifest = yamldecode(file("${path.module}/issuers/letsencrypt-prod.yaml"))
}

