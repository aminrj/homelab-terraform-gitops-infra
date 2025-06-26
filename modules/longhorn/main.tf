terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
    }
  }
}

resource "helm_release" "longhorn" {
  name             = "longhorn"
  chart            = "longhorn"
  repository       = "https://charts.longhorn.io"
  version          = "1.8.2"
  namespace        = "longhorn-system"
  create_namespace = true
  
  # CRITICAL: Add these for stability
  timeout         = 600  # 10 minutes timeout
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  
  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      default_data_path      = var.default_data_path
      default_replica_count  = var.default_replica_count
      kubelet_root_dir       = var.kubelet_root_dir
      ui_service_type        = var.ui_service_type
    })
  ]
}

# Wait for Longhorn to be fully ready before node configuration
resource "time_sleep" "wait_for_longhorn" {
  depends_on = [helm_release.longhorn]
  create_duration = "120s"  # Wait 2 minutes for Longhorn to initialize
}

# ENHANCED: Proper node preparation with validation
resource "null_resource" "prepare_longhorn_nodes" {
  depends_on = [time_sleep.wait_for_longhorn]
  
  # Trigger re-run if Longhorn is updated
  triggers = {
    longhorn_version = helm_release.longhorn.version
    config_hash     = md5(templatefile("${path.module}/values.yaml.tpl", {
      default_data_path      = var.default_data_path
      default_replica_count  = var.default_replica_count
      kubelet_root_dir       = var.kubelet_root_dir
      ui_service_type        = var.ui_service_type
    }))
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "🔧 Configuring Longhorn nodes..."
      
      # Wait for Longhorn manager pods to be ready
      echo "⏳ Waiting for Longhorn manager to be ready..."
      kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
      
      # Wait for CSI driver to be ready
      echo "⏳ Waiting for CSI driver to be ready..."
      kubectl wait --for=condition=ready pod -l app=longhorn-csi-plugin -n longhorn-system --timeout=300s
      
      # Configure worker nodes for storage
      echo "🏷️ Configuring worker nodes..."
      kubectl label node microk8s-prod-llm1 node.longhorn.io/create-default-disk=true --overwrite
      kubectl label node microk8s-prod-node1 node.longhorn.io/create-default-disk=true --overwrite
      
      # Configure control plane node (no storage)
      echo "🏷️ Configuring control plane node..."
      kubectl label node microk8snode1 node.longhorn.io/create-default-disk=false --overwrite
      
      # Verify Longhorn nodes are ready
      echo "✅ Verifying Longhorn nodes..."
      kubectl wait --for=condition=ready nodes.longhorn.io --all -n longhorn-system --timeout=300s
      
      # Create a test PVC to validate the setup
      echo "🧪 Testing storage provisioning..."
      cat <<EOF | kubectl apply -f -
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: longhorn-test-pvc
        namespace: default
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 1Gi
      EOF
      
      # Wait for PVC to be bound
      kubectl wait --for=condition=Bound pvc/longhorn-test-pvc -n default --timeout=120s
      
      # Clean up test PVC
      kubectl delete pvc longhorn-test-pvc -n default
      
      echo "🎉 Longhorn configuration completed successfully!"
    EOT
  }
  
  # Cleanup on destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "🧹 Cleaning up Longhorn node labels..."
      kubectl label nodes --all node.longhorn.io/create-default-disk- --ignore-not-found=true || true
    EOT
  }
}

# OPTIONAL: Create additional storage classes for different use cases
resource "kubectl_manifest" "longhorn_fast_storage_class" {
  depends_on = [null_resource.prepare_longhorn_nodes]
  
  yaml_body = <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
  dataLocality: "disabled"
  replicaAutoBalance: "ignored"
YAML
}

# Output Longhorn UI URL
output "longhorn_ui_url" {
  description = "Longhorn UI URL"
  value       = var.ui_service_type == "LoadBalancer" ? "https://10.0.30.201" : "Use kubectl port-forward to access the UI"
}

# Output storage classes
output "storage_classes" {
  description = "Available storage classes"
  value = [
    "longhorn (default)",
    "longhorn-fast"
  ]
}
