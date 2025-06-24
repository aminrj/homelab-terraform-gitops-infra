
defaultSettings:
  defaultDataPath: "${default_data_path}"
  defaultReplicaCount: ${default_replica_count}
  replicaSoftAntiAffinity: true
  replicaAutoBalance: "best-effort"
  nodeDownPodDeletionPolicy: "delete-both-statefulset-and-deployment-pod"
  disableSchedulingOnCordonedNode: true
  disableSchedulingOnNodeWithIsolatedReplica: false
  concurrentReplicaRebuildPerNodeLimit: 1
  storageOverProvisioningPercentage: 100
  volumeBindingMode: WaitForFirstConsumer
  dataLocality: best-effort
  # Critical missing settings for PVC reliability
  createDefaultDiskLabeledNodes: true
  defaultDataLocality: "disabled"
  replicaDiskSoftAntiAffinity: false
  storageMinimalAvailablePercentage: 25
  upgradeChecker: false
  # Filesystem and formatting settings
  mkfsExt4Parameters: "-F"  # Force filesystem creation
  removeSnapshotsDuringFilesystemTrim: "ignored"

service:
  ui:
    type: ${ui_service_type}
    loadBalancerIP: "10.0.30.201"

csi:
  kubeletRootDir: "${kubelet_root_dir}"
  # Additional CSI settings for better reliability
  attacherReplicaCount: 1
  provisionerReplicaCount: 1
  resizerReplicaCount: 1
  snapshotterReplicaCount: 1

# Add storage class configuration
storageClass:
  create: true
  name: "longhorn"
  isDefaultClass: true
  allowVolumeExpansion: true
  reclaimPolicy: "Delete"  # Critical: ensures proper cleanup
  volumeBindingMode: "Immediate"  # Override the default setting for storage class
  parameters:
    numberOfReplicas: "${default_replica_count}"
    staleReplicaTimeout: "2880"
    fromBackup: ""
    fsType: "ext4"
    dataLocality: "disabled"  # Start with disabled for reliability
    replicaAutoBalance: "ignored"

persistence:
  defaultClass: true
  defaultClassReplicaCount: ${default_replica_count}
  reclaimPolicy: Delete

# Node selector and tolerations for Longhorn components
longhornManager:
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"

longhornDriver:
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"

ui:
  enabled: true
  replicas: 2
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"
    - key: "node.kubernetes.io/not-ready"
      operator: "Exists"
      effect: "NoExecute"
    - key: "node.kubernetes.io/unreachable"
      operator: "Exists"
      effect: "NoExecute"
  nodeSelector: {}
  affinity: {}
  resources:
    requests:
      cpu: 50m
      memory: 50Mi
    limits:
      cpu: 250m
      memory: 128Mi
