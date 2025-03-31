
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}

resource "kubernetes_namespace" "cnpg" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_storage_class" "cnpg_longhorn" {
  metadata {
    name = "${var.namespace}-longhorn"
  }

  provisioner = "driver.longhorn.io"

  parameters = {
    numberOfReplicas = "1"
    staleReplicaTimeout = "30"
  }

  reclaim_policy        = "Retain"
  volume_binding_mode   = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

resource "helm_release" "cloudnativepg" {
  name             = var.release_name
  namespace        = var.namespace
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = var.chart_version
  create_namespace = false # we already created it

  values = [file("${path.module}/values.yaml")]
}


