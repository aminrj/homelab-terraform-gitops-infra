# Fixed Longhorn Configuration for Production Stability

defaultSettings:
  # Storage paths and replication
  defaultDataPath: "${default_data_path}"
  defaultReplicaCount: ${default_replica_count}
  
  # CRITICAL FIX: Prevent multi-attach issues
  replicaSoftAntiAffinity: false  # Changed from true - forces hard anti-affinity
  replicaAutoBalance: "ignored"   # Disable auto-balancing initially for stability
  
  # Node and Pod management - FIXED SETTINGS
  nodeDownPodDeletionPolicy: "delete-both-statefulset-and-deployment-pod"
  disableSchedulingOnCordonedNode: true
  disableSchedulingOnNodeWithIsolatedReplica: true  # Changed to true
  concurrentReplicaRebuildPerNodeLimit: 1
  
  # Storage provisioning - CONSERVATIVE SETTINGS
  storageOverProvisioningPercentage: 200  # More conservative
  storageMinimalAvailablePercentage: 25
  
  # Volume binding and locality - CRITICAL FIXES
  volumeBindingMode: "Immediate"  # Changed from WaitForFirstConsumer
  dataLocality: "disabled"        # Start with disabled for maximum stability
  defaultDataLocality: "disabled"
  
  # Disk and replica management
  createDefaultDiskLabeledNodes: true
  replicaDiskSoftAntiAffinity: true  # Changed to true for better distribution
  
  # Filesystem settings - CRITICAL FOR YOUR ISSUE
  mkfsExt4Parameters: "-F -E lazy_itable_init=0,lazy_journal_init=0"  # Force fast format
  removeSnapshotsDuringFilesystemTrim: "ignored"
  
  # Stability and performance
  upgradeChecker: false
  priorityClass: "system-cluster-critical"
  
  # CRITICAL: CSI timeout settings to prevent mount failures
  csiAttacherTimeout: "300s"
  csiProvisionerTimeout: "300s"
  csiMountDeviceTimeout: "300s"
  
  # Orphaned resource cleanup
  orphanedResourceDeletionPolicy: "delete-if-not-in-use"
  deletingConfirmationFlag: true

# Service configuration
service:
  ui:
    type: ${ui_service_type}
    loadBalancerIP: "10.0.30.201"

# CSI Driver settings - ENHANCED FOR STABILITY
csi:
  kubeletRootDir: "${kubelet_root_dir}"
  attacherReplicaCount: 1
  provisionerReplicaCount: 1
  resizerReplicaCount: 1
  snapshotterReplicaCount: 1
  
  # CRITICAL: Enhanced CSI settings
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"
  
  # Resource limits for CSI components
  attacherResources:
    requests:
      cpu: 10m
      memory: 50Mi
    limits:
      cpu: 100m
      memory: 128Mi
  
  provisionerResources:
    requests:
      cpu: 10m
      memory: 50Mi
    limits:
      cpu: 100m
      memory: 128Mi

# Storage class configuration - FIXED SETTINGS
storageClass:
  create: true
  name: "longhorn"
  isDefaultClass: true
  allowVolumeExpansion: true
  reclaimPolicy: "Delete"
  volumeBindingMode: "Immediate"  # Critical: immediate binding
  parameters:
    numberOfReplicas: "${default_replica_count}"
    staleReplicaTimeout: "2880"  # 48 hours
    fromBackup: ""
    fsType: "ext4"
    dataLocality: "disabled"     # Start with disabled
    replicaAutoBalance: "ignored"
    
    # CRITICAL: Mount options for reliability
    mountOptions: "defaults,noatime"
    
    # Prevent multi-attach issues
    diskSelector: ""
    nodeSelector: ""

# Persistence settings
persistence:
  defaultClass: true
  defaultClassReplicaCount: ${default_replica_count}
  reclaimPolicy: "Delete"

# Manager configuration - ENHANCED
longhornManager:
  priorityClass: "system-cluster-critical"
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"
    - key: "node.kubernetes.io/not-ready"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 30
    - key: "node.kubernetes.io/unreachable"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 30
  
  # Resource limits
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Driver configuration - ENHANCED
longhornDriver:
  priorityClass: "system-cluster-critical"
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"
    - key: "node.kubernetes.io/not-ready"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 30
    - key: "node.kubernetes.io/unreachable"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 30

# UI configuration - STABLE SETTINGS
ui:
  enabled: true
  replicas: 1  # Reduced from 2 for stability
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"
  
  # Resource limits
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
  
  # Node affinity to prefer worker nodes
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: node-role.kubernetes.io/control-plane
            operator: DoesNotExist

# Instance Manager settings - CRITICAL FOR STABILITY
instanceManager:
  image: longhornio/longhorn-instance-manager:v1.8.2
  
  # Resource limits for instance managers
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 300m
      memory: 512Mi









