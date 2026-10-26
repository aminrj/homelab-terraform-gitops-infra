resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.12.0" # via 0.16.2 and a v1 storage migration (2026-10-26)

  values = [
    yamlencode({
      installCRDs : true

      # Required to process ClusterSecretStores across namespaces
      processClusterStore : true
      processClusterExternalSecret : true

      # Full cluster RBAC permissions to read ClusterSecretStores and secrets across namespaces
      rbac : {
        create : true
        clusterWide : true
      }

      serviceAccount : {
        create : true
        name : "external-secrets-sa"
      }

      controllerClass : "" # optional, only set this if you want multiple ESO controllers

      webhook : {
        create : true
      }

      certController : {
        create : true
      }
    })
  ]
}
