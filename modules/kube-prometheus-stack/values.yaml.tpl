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
              storage: 10Gi

    podMonitorSelector: {}                # Allow PodMonitors without label restriction
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorNamespaceSelector: {}       # Allow PodMonitors from any namespace
    serviceMonitorSelector: {}            # Also allow ServiceMonitors from any namespace

grafana:
  adminPassword: "mysecurepassword"
  service:
    type: LoadBalancer
  persistence:
    enabled: true
    size: 10Gi
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
    storage:
      volumeClaimTemplate:
  spec:
          storageClassName: "${storage_class}"
          accessModes: ["ReadWriteOnce"]
  
