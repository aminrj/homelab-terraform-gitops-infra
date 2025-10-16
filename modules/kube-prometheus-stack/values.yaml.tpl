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
        cpu: "100m"          # Minimal CPU requirement
      limits:
        memory: "1Gi"        # Conservative memory limit
        cpu: "500m"          # Conservative CPU limit

    # Allow scheduling on control plane when necessary
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule

    # Scraping and evaluation optimization
    scrapeInterval: "30s"              # Default scrape interval
    evaluationInterval: "30s"          # Rule evaluation interval

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

grafana:
  priorityClassName: "${priority_class_name}"
  service:
    type: LoadBalancer
    loadBalancerIP: "10.0.30.203"
  persistence:
    enabled: true
    size: 20Gi
    storageClassName: "${storage_class}"
    accessModes: ["ReadWriteOnce"]
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

    route:
      group_by: ['alertname', 'severity']
      group_wait: 10s
      group_interval: 5m
      repeat_interval: 30m
      receiver: slack-notifications
      routes:
        - match:
            severity: critical
          receiver: slack-notifications

    receivers:
      - name: slack-notifications
        slack_configs:
          - channel: '#homelab-stuff'
            send_resolved: true
            username: 'prometheus-alertmanager'
            icon_emoji: ':warning:'
            api_url: '${slack_webhook_url}'

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
