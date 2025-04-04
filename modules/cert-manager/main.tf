resource "helm_release" "cert_manager_crds" {
  name       = "cert-manager-crds"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.0"

  # Only install the CRDs from this chart
  # For older versions of the chart, the variable may differ (installCRDs or crds.create).
  set {
    name  = "installCRDs"
    value = "true"
  }

  # Do NOT actually deploy the rest of cert-manager here, so turn off the normal deployment
  set {
    name  = "replicaCount"
    value = 0
  }

  # If needed, also override any other fields that create normal cert-manager resources
  # so that effectively only the CRDs are installed in this release.
}

# Wait for CRDs to be registered
resource "time_sleep" "wait_for_crds" {
  depends_on = [helm_release.cert_manager_crds]
  create_duration = "10s"
}

resource "helm_release" "cert_manager_app" {
  depends_on = [time_sleep.wait_for_crds]
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.0"
  namespace  = "cert-manager"
  create_namespace = true
  wait       = true

  # Here we turn off installing CRDs so that we don't conflict with cert_manager_crds
  set {
    name  = "installCRDs"
    value = "false"
  }
}

# Now that the CRDs and the controller are definitely in place...
resource "kubernetes_manifest" "letsencrypt_staging" {
  depends_on = [helm_release.cert_manager_app]
  manifest = yamldecode(file("${path.module}/issuers/letsencrypt-staging.yaml"))
}

resource "kubernetes_manifest" "letsencrypt_prod" {
  depends_on = [helm_release.cert_manager_app]
  manifest = yamldecode(file("${path.module}/issuers/letsencrypt-prod.yaml"))
}
