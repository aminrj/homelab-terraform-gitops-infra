prometheus:
  retention: "5d"
  walCompression: true
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: "${storage_class}"
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi

    nodeSelector:
      kubernetes.io/hostname: microk8s-prod-llm1

    podMonitorSelector: {}
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorNamespaceSelector: {}
    serviceMonitorSelector: {}

grafana:
  service:
    type: LoadBalancer
    loadBalancerIP: "10.0.30.203"
  persistence:
    enabled: true
    size: 20Gi
    storageClassName: "${storage_class}"
    accessModes: ["ReadWriteOnce"]
  nodeSelector:
    kubernetes.io/hostname: microk8s-prod-llm1
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
    datasources:
      enabled: true

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: "${storage_class}"
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
    nodeSelector:
      kubernetes.io/hostname: microk8s-prod-llm1

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
          - channel: '#alerts'
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
