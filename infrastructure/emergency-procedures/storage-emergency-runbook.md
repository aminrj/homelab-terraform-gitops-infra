# Emergency Storage Recovery Runbook

## Overview

This runbook provides step-by-step procedures for handling storage emergencies in the MicroK8s cluster. These procedures are designed to restore cluster functionality when storage exhaustion threatens or occurs.

## Emergency Classification

### 🚨 **CRITICAL** - Storage >95% Full
- **Impact**: Immediate cluster failure risk
- **Response Time**: < 5 minutes
- **Actions**: Execute emergency cleanup immediately

### ⚠️ **HIGH** - Storage >85% Full
- **Impact**: Performance degradation, pod scheduling failures
- **Response Time**: < 30 minutes
- **Actions**: Immediate proactive cleanup

### ℹ️ **MEDIUM** - Storage >75% Full
- **Impact**: Monitoring alerts, potential issues
- **Response Time**: < 2 hours
- **Actions**: Scheduled cleanup and investigation

## Emergency Response Procedures

### Phase 1: Immediate Triage (0-5 minutes)

#### 1. Assess Cluster Health
```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Check critical system pods
kubectl get pods -n kube-system | grep -E "(coredns|traefik|calico)"

# Verify API server responsiveness
kubectl get ns
```

#### 2. Check Storage Usage
```bash
# Check node disk usage
kubectl top nodes

# Check PV status
kubectl get pv --sort-by=.spec.capacity.storage

# Check pods with storage issues
kubectl get pods --all-namespaces | grep -E "(Pending|Error|CrashLoopBackOff)"
```

#### 3. Identify Storage Hotspots
```bash
# Find largest PVCs
kubectl get pvc --all-namespaces --sort-by=.spec.resources.requests.storage

# Check database storage usage
kubectl get clusters --all-namespaces -o wide

# Check for failed mount issues
kubectl describe nodes | grep -A5 -B5 "disk pressure"
```

### Phase 2: Emergency Cleanup (5-15 minutes)

#### 1. Quick Container Image Cleanup
```bash
# On each node (SSH or console access required)
sudo microk8s.crictl images prune -a

# Remove unused container data
sudo microk8s.crictl rmi --prune

# Clean Docker/containerd cache
sudo journalctl --vacuum-time=1d
```

#### 2. Emergency PV Cleanup
```bash
# List Released PVs for immediate deletion
kubectl get pv | grep Released

# Force delete Released PVs (EMERGENCY ONLY)
kubectl get pv | grep Released | awk '{print $1}' | head -5 | xargs kubectl delete pv

# Clean up completed/failed pods
kubectl delete pods --all-namespaces --field-selector=status.phase=Failed
kubectl delete pods --all-namespaces --field-selector=status.phase=Succeeded
```

#### 3. Log Cleanup
```bash
# Clean system logs on nodes
sudo journalctl --vacuum-size=100M

# Clean Kubernetes pod logs
for pod in $(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'); do
  ns=$(echo $pod | cut -d' ' -f1)
  name=$(echo $pod | cut -d' ' -f2)
  kubectl logs --tail=100 -n $ns $name > /dev/null 2>&1 || true
done
```

### Phase 3: Service Recovery (15-30 minutes)

#### 1. Restart Critical Services
```bash
# Restart kubelet on problematic nodes
sudo systemctl restart snap.microk8s.daemon-kubelet

# Restart containerd if needed
sudo systemctl restart snap.microk8s.daemon-containerd

# Force garbage collection
kubectl delete pods -n kube-system --field-selector=status.phase=Failed
```

#### 2. Database Recovery
```bash
# Check database cluster status
kubectl get clusters --all-namespaces

# For failed database clusters, check logs
kubectl logs -n cnpg-prod -l app.kubernetes.io/name=cloudnative-pg

# Restart database pods if needed
kubectl delete pod -n cnpg-prod -l postgresql=linkding-db-cnpg-v1
```

#### 3. Application Recovery
```bash
# Check application status
kubectl get pods --all-namespaces | grep -v Running

# Restart problematic applications
kubectl rollout restart deployment -n prod linkding
kubectl rollout restart deployment -n prod n8n

# Force reschedule if needed
kubectl delete pod -n prod -l app=linkding --force --grace-period=0
```

### Phase 4: Validation and Monitoring (30-60 minutes)

#### 1. Verify Cluster Health
```bash
# Check all nodes are Ready
kubectl get nodes

# Verify all critical pods are Running
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Test cluster functionality
kubectl create job test-job --image=busybox -- echo "Cluster test successful"
kubectl wait --for=condition=complete job/test-job --timeout=60s
kubectl delete job test-job
```

#### 2. Storage Verification
```bash
# Confirm storage usage is reduced
kubectl top nodes

# Check PV status
kubectl get pv --sort-by=.spec.capacity.storage

# Verify database connectivity
kubectl exec -n cnpg-prod linkding-db-cnpg-v1-1 -- psql -U postgres -c "SELECT 1;"
```

#### 3. Application Testing
```bash
# Test external access
curl -k https://linkding.k8s.lanhub.casa/health/

# Check ArgoCD sync status
kubectl get applications -n argocd | grep -v Synced
```

## Emergency Contact and Escalation

### Internal Actions
1. **Document the incident** - Create incident log with timeline
2. **Notify stakeholders** - Update on progress and ETA
3. **Schedule post-incident review** - Analyze root cause

### Escalation Criteria
- **Cluster completely unresponsive** after 30 minutes
- **Data corruption detected** in databases
- **Multiple node failures** affecting availability
- **Security compromise** suspected

## Recovery Validation Checklist

- [ ] All nodes show Ready status
- [ ] All critical system pods Running
- [ ] Database clusters healthy
- [ ] Applications accessible externally
- [ ] Storage usage below 75%
- [ ] ArgoCD applications Synced
- [ ] Monitoring and alerts functional
- [ ] Backup jobs running normally

## Post-Emergency Actions

### Immediate (0-24 hours)
1. **Root cause analysis** - Identify what caused storage exhaustion
2. **Implement preventive measures** - Adjust monitoring thresholds
3. **Update runbooks** - Document lessons learned
4. **Test backup systems** - Verify backup integrity

### Short-term (1-7 days)
1. **Review storage policies** - Adjust PV reclaim policies
2. **Optimize applications** - Reduce storage footprint
3. **Implement automation** - Deploy storage cleanup jobs
4. **Train team members** - Ensure knowledge transfer

### Long-term (1-4 weeks)
1. **Capacity planning** - Project future storage needs
2. **Infrastructure improvements** - Consider distributed storage
3. **Process improvements** - Automate emergency procedures
4. **Documentation updates** - Keep runbooks current

## Emergency Script Locations

- Emergency cleanup script: `/scripts/emergency-storage-cleanup.sh`
- Node recovery script: `/scripts/node-recovery.sh`
- Database recovery script: `/scripts/database-emergency-recovery.sh`

## Key Commands Reference

```bash
# Quick storage check
kubectl top nodes && kubectl get pv | grep Released | wc -l

# Emergency cleanup one-liner
kubectl delete pods --all-namespaces --field-selector=status.phase=Failed && kubectl get pv | grep Released | head -3 | awk '{print $1}' | xargs kubectl delete pv

# Force restart all deployments
kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | xargs -n2 sh -c 'kubectl rollout restart deployment/$1 -n $0'
```