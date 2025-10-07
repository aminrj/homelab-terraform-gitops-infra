# modules/microceph/main.tf

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

# ServiceMonitor to scrape MicroCeph manager metrics
resource "kubectl_manifest" "microceph_mgr_servicemonitor" {
  validate_schema    = false
  server_side_apply  = true
  wait_for_rollout   = true
  
  yaml_body = <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: microceph-mgr
  namespace: ${var.monitoring_namespace}
  labels:
    app: microceph-mgr
    release: ${var.prometheus_release_name}
spec:
  endpoints:
  - port: prometheus
    path: /metrics
    interval: 30s
  selector:
    matchLabels:
      app: microceph-mgr
YAML
}

# Headless service for MicroCeph managers
resource "kubernetes_service" "microceph_mgr" {
  metadata {
    name      = "microceph-mgr"
    namespace = var.monitoring_namespace
    labels = {
      app = "microceph-mgr"
    }
  }
  spec {
    cluster_ip = "None"
    port {
      name        = "prometheus"
      port        = 9283
      target_port = 9283
    }
  }
}

# Endpoints for MicroCeph manager
resource "kubernetes_endpoints" "microceph_mgr" {
  metadata {
    name      = "microceph-mgr"
    namespace = var.monitoring_namespace
  }
  subset {
    address {
      ip = var.microceph_manager_ip
    }
    port {
      name = "prometheus"
      port = 9283
    }
  }
}

# MicroCeph storage alerts
resource "kubectl_manifest" "microceph_storage_alerts" {
  yaml_body = <<YAML
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: microceph-storage-alerts
  namespace: ${var.monitoring_namespace}
  labels:
    app: kube-prometheus-stack
    release: ${var.prometheus_release_name}
spec:
  groups:
  - name: microceph.storage.rules
    rules:
    - alert: CephClusterNearFull
      expr: (ceph_cluster_total_used_raw_bytes / ceph_cluster_total_bytes) > 0.75
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: Ceph cluster is getting full
        description: "Ceph cluster usage is {{ $value | humanizePercentage }} (above 75%)"
    - alert: CephClusterCriticallyFull
      expr: (ceph_cluster_total_used_raw_bytes / ceph_cluster_total_bytes) > 0.85
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: Ceph cluster is critically full
        description: "Ceph cluster usage is {{ $value | humanizePercentage }} (above 85%)"
    - alert: CephOSDDown
      expr: ceph_osd_up == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: Ceph OSD is down
        description: "Ceph OSD {{ $labels.ceph_daemon }} is down for more than 5 minutes"
    - alert: CephMonDown
      expr: ceph_mon_quorum_status == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: Ceph monitor is out of quorum
        description: "Ceph monitor {{ $labels.ceph_daemon }} is not in quorum"
    - alert: PVCStorageRunningLow
      expr: (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.8
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: PVC storage running low
        description: "PVC {{ $labels.persistentvolumeclaim }} in namespace {{ $labels.namespace }} is {{ $value | humanizePercentage }} full"
    - alert: PVCStorageCritical
      expr: (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.9
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: PVC storage critically low
        description: "PVC {{ $labels.persistentvolumeclaim }} in namespace {{ $labels.namespace }} is {{ $value | humanizePercentage }} full"
YAML
}
