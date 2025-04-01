
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

grafana:
  adminPassword: "mysecurepassword"
  service:
    type: LoadBalancer
  persistence:
    enabled: true
    size: 10Gi
    storageClassName: "${storage_class}"
    accessModes: ["ReadWriteOnce"]

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: "${storage_class}"
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi



