defaultSettings:
  defaultDataPath: "${default_data_path}"
  defaultReplicaCount: ${default_replica_count}

service:
  ui:
    type: ${ui_service_type}
    loadBalancerIP: "10.0.30.201"

csi:
  kubeletRootDir: "${kubelet_root_dir}"

ui:
  enabled: true
  replicas: 2
  tolerations: []
  nodeSelector: {}
  affinity: {}
  resources:
    requests:
      cpu: 50m
      memory: 50Mi
    limits:
      cpu: 250m
      memory: 128Mi
