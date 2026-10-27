# Helm never upgrades CRDs; this pre-upgrade job applies the operator's CRDs (server-side)
# before each chart upgrade.
crds:
  enabled: true
  upgradeJob:
    enabled: true

prometheus:
  prometheusSpec:
    priorityClassName: "${priority_class_name}"
    # CRITICAL: Prevent storage exhaustion with multiple safety limits
    retention: "7d"                    # Time-based retention: 7 days max
    retentionSize: "15GB"              # Size-based retention: 15GB max (75% of 20GB)

    # Storage efficiency and performance
    walCompression: true               # Compress WAL files (30-50% savings)

    # Storage configuration
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: "${storage_class}"
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi

    # Resource limits heavily optimized for cluster capacity
    resources:
      requests:
        memory: "512Mi"      # Minimal memory requirement
        cpu: "300m"          # Minimal CPU requirement
      limits:
        memory: "2Gi"        # Conservative memory limit
        cpu: "1000m"          # Conservative CPU limit

    # Allow scheduling on control plane when necessary
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule

    # Scraping and evaluation optimization
    scrapeInterval: "60s"              # Default scrape interval
    evaluationInterval: "60s"          # Rule evaluation interval

    # Query optimization
    queryTimeout: "2m"                 # Prevent long-running queries
    queryMaxConcurrency: 20            # Limit concurrent queries

    # TSDB optimization for storage efficiency
    tsdb:
      outOfOrderTimeWindow: "0s"       # Disable out-of-order samples (saves space)

    # Remote write configuration (for external storage if needed)
    # remoteWrite: []                  # Disabled by default

    # Service discovery optimization
    podMonitorSelector: {}
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorNamespaceSelector: {}
    serviceMonitorSelector: {}
    serviceMonitorSelectorNilUsesHelmValues: false   # every ServiceMonitor (pve-exporter, cert-manager), not only release=kube-prometheus-stack
    serviceMonitorNamespaceSelector: {}

grafana:
  priorityClassName: "${priority_class_name}"
  admin:
    existingSecret: grafana-admin   # Terraform, from modules/admin-passwords
    userKey: admin-user
    passwordKey: admin-password
  # https://grafana.lab.aminrj.com through Traefik; the LoadBalancer IP stays as a fallback.
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - grafana.lab.aminrj.com
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.lab.aminrj.com
  grafana.ini:
    server:
      root_url: https://grafana.lab.aminrj.com
  service:
    type: LoadBalancer
    loadBalancerIP: "10.0.30.203"
  persistence:
    enabled: true
    size: 20Gi
    storageClassName: "${storage_class}"
    accessModes: ["ReadWriteOnce"]
  initChownData:
    enabled: false
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
    datasources:
      enabled: true

alertmanager:
  alertmanagerSpec:
    priorityClassName: "${priority_class_name}"
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: "${storage_class}"
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

  config:
    global:
      resolve_timeout: 5m

    # Alerts become iPhone notifications through Home Assistant (homelab-foundation
    # homeassistant/config/packages/lab_alerts.yaml): a webhook inside SERVICES, no internet hop.
    route:
      group_by: ['alertname', 'severity']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: %{ if ha_webhook_id != "" }home-assistant%{ else }silent%{ endif }
      routes:
        - matchers: ['alertname =~ "Watchdog|InfoInhibitor"']
          receiver: silent
        - matchers: ['job = "microceph-mgr"']
          receiver: silent

    receivers:
      - name: silent
%{ if ha_webhook_id != "" ~}
      - name: home-assistant
        webhook_configs:
          - url: 'http://10.0.30.40:8123/api/webhook/${ha_webhook_id}'
            send_resolved: true
            max_alerts: 10
%{ endif ~}

    inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'instance']

additionalPrometheusRulesMap:
  resource-pressure-alerts:
    groups:
      - name: resource.rules
        rules:
          - alert: NodeCPUHigh
            expr: (100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 90
            for: 2m
            labels:
              severity: warning
            annotations:
              summary: "High CPU usage on node {{ $labels.instance }}"
              description: "Node {{ $labels.instance }} CPU usage is above 90%."

          - alert: NodeMemoryHigh
            expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
            for: 2m
            labels:
              severity: warning
            annotations:
              summary: "Low available memory on {{ $labels.instance }}"
              description: "{{ $labels.instance }} has less than 10% memory available."

          - alert: FilesystemSpaceLow
            expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
            for: 2m
            labels:
              severity: warning
            annotations:
              summary: "Low disk space on {{ $labels.instance }}"
              description: "{{ $labels.instance }} is below 15% disk space on root filesystem."

kubeControllerManager:
  enabled: false

kubeScheduler:
  enabled: false

kubeProxy:
  enabled: false
