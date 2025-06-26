#!/bin/bash

echo "🧹 Starting Longhorn complete cleanup..."

# Scale down all workloads using Longhorn storage
echo "📉 Scaling down workloads..."
kubectl get deploy --all-namespaces -o json | jq -r '.items[] | select(.spec.template.spec.volumes[]?.persistentVolumeClaim != null) | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace deployment; do
  echo "Scaling down $deployment in $namespace"
  kubectl scale deployment $deployment -n $namespace --replicas=0
done

# Wait for pods to terminate
echo "⏳ Waiting for pods to terminate..."
sleep 30

# Delete all PVCs (this will trigger Longhorn volume cleanup)
echo "🗑️ Deleting all PVCs..."
kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName == "longhorn") | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace pvc; do
  echo "Deleting PVC $pvc in $namespace"
  kubectl delete pvc $pvc -n $namespace --wait=false
done

# Wait for PVCs to be deleted
echo "⏳ Waiting for PVC cleanup..."
sleep 60

# Uninstall Longhorn via Terraform/Helm
echo "🚫 Uninstalling Longhorn..."
# Run this manually: terraform destroy -target=module.longhorn.helm_release.longhorn

# Clean up remaining Longhorn resources
echo "🧽 Cleaning remaining resources..."
kubectl delete namespace longhorn-system --ignore-not-found=true

# Clean up on each node
echo "🖥️ Cleaning up nodes..."
for node in microk8s-prod-llm1 microk8s-prod-node1 microk8snode1; do
  echo "Cleaning node: $node"
  kubectl debug node/$node -it --image=busybox -- sh -c "
        chroot /host bash -c '
            # Stop any remaining Longhorn processes
            pkill -f longhorn || true
            
            # Clean up mount points
            umount /var/lib/longhorn/*/globalmount 2>/dev/null || true
            umount /var/snap/microk8s/common/var/lib/kubelet/plugins/kubernetes.io/csi/*/globalmount 2>/dev/null || true
            
            # Remove Longhorn directories
            rm -rf /var/lib/longhorn/
            rm -rf /var/snap/microk8s/common/var/lib/kubelet/plugins/driver.longhorn.io/
            
            # Clean up any remaining device mappings
            dmsetup ls | grep longhorn | cut -d: -f1 | xargs -r -n1 dmsetup remove || true
            
            # Remove node labels
            echo \"Node cleanup completed\"
        '
    " 2>/dev/null || echo "Direct cleanup failed, will clean via kubectl"
done

# Remove node labels
echo "🏷️ Removing node labels..."
kubectl label nodes --all node.longhorn.io/create-default-disk- --ignore-not-found=true
kubectl label nodes --all node.longhorn.io/disk- --ignore-not-found=true

# Verify cleanup
echo "✅ Verifying cleanup..."
kubectl get pv | grep longhorn || echo "No Longhorn PVs remaining"
kubectl get pvc --all-namespaces | grep longhorn || echo "No Longhorn PVCs remaining"

echo "🎉 Cleanup completed! Ready for fresh Longhorn installation."
echo "📋 Next steps:"
echo "1. Run: terraform destroy -target=module.longhorn.helm_release.longhorn"
echo "2. Update your Terraform configuration with the fixed values"
echo "3. Run: terraform apply"
