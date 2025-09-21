# Node Failure Recovery Procedures

## Overview

This document provides comprehensive procedures for recovering from node failures in the MicroK8s homelab cluster. These procedures are designed to restore cluster functionality while preserving data integrity and minimizing service disruption.

## Node Failure Classifications

### 🔴 **CRITICAL** - Control Plane Node Failure
- **Impact**: Cluster API unavailable, no pod scheduling
- **Response Time**: < 15 minutes
- **Recovery**: Emergency control plane restoration

### 🟠 **HIGH** - Multiple Worker Node Failure
- **Impact**: Service degradation, potential data loss
- **Response Time**: < 30 minutes
- **Recovery**: Load redistribution and replacement

### 🟡 **MEDIUM** - Single Worker Node Failure
- **Impact**: Reduced capacity, automatic failover
- **Response Time**: < 2 hours
- **Recovery**: Node replacement or repair

### 🟢 **LOW** - Temporary Node Unavailability
- **Impact**: Temporary performance impact
- **Response Time**: < 4 hours
- **Recovery**: Monitor for auto-recovery

## Pre-Recovery Assessment

### 1. Cluster Status Assessment
```bash
# Check overall cluster health
kubectl cluster-info
kubectl get nodes -o wide

# Check node conditions
kubectl describe nodes | grep -A5 "Conditions:"

# Verify critical system pods
kubectl get pods -n kube-system | grep -E "(coredns|traefik|calico)"

# Check storage availability
kubectl get pv --sort-by=.spec.capacity.storage
```

### 2. Workload Impact Analysis
```bash
# Check affected applications
kubectl get pods --all-namespaces -o wide | grep -v Running

# Identify pods on failed nodes
kubectl get pods --all-namespaces --field-selector spec.nodeName=<failed-node>

# Check database cluster status
kubectl get clusters --all-namespaces -o wide

# Verify external access
curl -k https://linkding.k8s.lanhub.casa/health/
```

### 3. Data Integrity Check
```bash
# Check PostgreSQL cluster health
kubectl cnpg status linkding-db-cnpg-v1 -n cnpg-prod

# Verify backup integrity
kubectl get scheduledbackups --all-namespaces

# Check PV status for orphaned volumes
kubectl get pv | grep -E "(Released|Failed)"
```

## Recovery Procedures by Scenario

### Scenario 1: Control Plane Node Failure

#### Phase 1: Emergency Assessment (0-5 minutes)
```bash
# Test cluster API availability
kubectl version --short

# Check etcd status (if accessible)
sudo microk8s.kubectl exec etcd-<node> -n kube-system -- etcdctl endpoint health

# Verify node network connectivity
ping <control-plane-node-ip>
ssh <control-plane-node-ip> "systemctl status snap.microk8s.daemon-apiserver"
```

#### Phase 2: Control Plane Recovery (5-15 minutes)
```bash
# Option A: Restart MicroK8s services on failed node
ssh <control-plane-node> "sudo microk8s stop && sudo microk8s start"

# Option B: Rebuild control plane from backup
# 1. Prepare new node with same IP
# 2. Restore etcd from backup
sudo microk8s.kubectl exec etcd-backup -n kube-system -- etcdctl snapshot restore /backup/etcd-snapshot.db

# Option C: Promote worker to control plane (if cluster has multiple nodes)
microk8s add-node --token-ttl 3600
# Run join command on replacement node
```

#### Phase 3: Validation (15-20 minutes)
```bash
# Verify API server functionality
kubectl cluster-info
kubectl get nodes

# Test pod scheduling
kubectl create job test-scheduling --image=busybox -- echo "Scheduling test"
kubectl wait --for=condition=complete job/test-scheduling --timeout=60s
kubectl delete job test-scheduling

# Verify system pods are running
kubectl get pods -n kube-system | grep -v Running
```

### Scenario 2: Worker Node Failure

#### Phase 1: Graceful Workload Migration (0-10 minutes)
```bash
# Drain the failed node (if still responsive)
kubectl drain <failed-node> --ignore-daemonsets --delete-emptydir-data

# For unresponsive nodes, force delete
kubectl delete node <failed-node> --force --grace-period=0

# Check pod rescheduling
kubectl get pods --all-namespaces | grep Pending
```

#### Phase 2: Storage and Data Recovery (10-25 minutes)
```bash
# Handle orphaned volumes
kubectl get pv | grep <failed-node>

# For local storage, recover data if possible
# Mount the storage from another node or backup location

# For database pods, verify cluster integrity
kubectl get clusters --all-namespaces
kubectl logs -n cnpg-prod -l postgresql=linkding-db-cnpg-v1

# Force PostgreSQL failover if needed
kubectl cnpg promote linkding-db-cnpg-v1-2 -n cnpg-prod
```

#### Phase 3: Node Replacement (25-45 minutes)
```bash
# Prepare replacement node
# 1. Install MicroK8s
sudo snap install microk8s --classic --channel=1.28/stable

# 2. Join to cluster
microk8s add-node --token-ttl 3600
# Execute join command on new node

# 3. Verify node addition
kubectl get nodes
kubectl label node <new-node> node-role.kubernetes.io/worker=worker

# 4. Test workload scheduling
kubectl get pods --all-namespaces -o wide | grep <new-node>
```

### Scenario 3: Storage System Failure

#### Phase 1: Storage Assessment (0-5 minutes)
```bash
# Check storage class availability
kubectl get storageclass

# Verify PV provisioning
kubectl get pv | grep -E "(Available|Bound|Released|Failed)"

# Check storage system pods
kubectl get pods -n rook-ceph # If using Rook-Ceph
kubectl get pods -n openebs   # If using OpenEBS
```

#### Phase 2: Emergency Storage Recovery (5-15 minutes)
```bash
# For MicroK8s hostpath storage
sudo systemctl status snap.microk8s.daemon-hostpath-provisioner

# Restart storage components
sudo microk8s disable hostpath-storage
sudo microk8s enable hostpath-storage

# For persistent storage issues, check mount points
df -h
mount | grep k8s
```

#### Phase 3: Data Recovery (15-30 minutes)
```bash
# Restore from database backups
kubectl get backups -n cnpg-prod

# Create restoration job
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: linkding-db-recovery
  namespace: cnpg-prod
spec:
  instances: 1
  bootstrap:
    recovery:
      backup:
        name: linkding-db-backup-<timestamp>
EOF

# Verify data integrity after restoration
kubectl exec -n cnpg-prod linkding-db-recovery-1 -- psql -U postgres -c "SELECT count(*) FROM django_migrations;"
```

## Network Failure Recovery

### Phase 1: Network Diagnosis (0-5 minutes)
```bash
# Check node network connectivity
kubectl get nodes -o wide
ping <node-ips>

# Verify CNI plugin status
kubectl get pods -n kube-system | grep calico
kubectl logs -n kube-system -l k8s-app=calico-node

# Check service networking
kubectl get svc --all-namespaces
nslookup kubernetes.default.svc.cluster.local
```

### Phase 2: CNI Recovery (5-15 minutes)
```bash
# Restart CNI components
kubectl delete pod -n kube-system -l k8s-app=calico-node

# For complete CNI failure, reset network
sudo microk8s disable calico
sudo microk8s enable calico

# Verify network functionality
kubectl exec -n default busybox -- nslookup kubernetes.default.svc.cluster.local
```

## Application-Specific Recovery

### Database Recovery (PostgreSQL with CNPG)
```bash
# Check cluster status
kubectl cnpg status <cluster-name> -n <namespace>

# View cluster events
kubectl describe cluster <cluster-name> -n <namespace>

# Manual failover if needed
kubectl cnpg promote <cluster-name>-<instance> -n <namespace>

# Backup verification
kubectl cnpg backup <cluster-name> -n <namespace>

# Point-in-time recovery
kubectl apply -f databases/linkding/overlays/prod/restore-from-prod.yaml
```

### Application Recovery (Linkding/N8N)
```bash
# Check application pod status
kubectl get pods -n prod

# View application logs
kubectl logs -n prod deployment/linkding
kubectl logs -n prod deployment/n8n

# Database connectivity test
kubectl exec -n prod deployment/linkding -- python manage.py check --database default

# Restart applications if needed
kubectl rollout restart deployment -n prod linkding
kubectl rollout restart deployment -n prod n8n

# Verify external access
curl -k https://linkding.k8s.lanhub.casa/health/
curl -k https://n8n.k8s.lanhub.casa/healthz
```

## Post-Recovery Validation

### 1. Cluster Health Check
```bash
# Verify all nodes are Ready
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system | grep -v Running

# Test cluster functionality
kubectl create namespace test-recovery
kubectl run test-pod --image=busybox --restart=Never -n test-recovery -- sleep 30
kubectl get pods -n test-recovery
kubectl delete namespace test-recovery
```

### 2. Application Validation
```bash
# Test database connectivity
kubectl exec -n cnpg-prod linkding-db-cnpg-v1-1 -- psql -U postgres -c "SELECT 1;"

# Verify application functionality
curl -k https://linkding.k8s.lanhub.casa/login/
curl -k https://n8n.k8s.lanhub.casa/

# Check ArgoCD sync status
kubectl get applications -n argocd | grep -v Synced
```

### 3. Monitoring and Alerting
```bash
# Verify Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
# Visit http://localhost:9090/targets

# Check alert status
# Visit http://localhost:9090/alerts

# Verify storage monitoring
kubectl get prometheusrules -n monitoring storage-critical-alerts
```

## Preventive Measures

### 1. Regular Health Checks
```bash
# Weekly cluster health script
#!/bin/bash
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
kubectl get pv | grep -E "(Released|Failed)"
kubectl top nodes
```

### 2. Backup Verification
```bash
# Monthly backup verification
kubectl get backups --all-namespaces
kubectl cnpg backup linkding-db-cnpg-v1 -n cnpg-prod

# Test restoration process quarterly
kubectl apply -f databases/linkding/test/restore-verification.yaml
```

### 3. Disaster Recovery Testing
```bash
# Quarterly DR test
# 1. Simulate node failure
# 2. Execute recovery procedures
# 3. Validate functionality
# 4. Document lessons learned
```

## Recovery Checklist Templates

### Node Failure Recovery Checklist
- [ ] Assess cluster status and impact
- [ ] Identify affected workloads
- [ ] Check data integrity
- [ ] Execute appropriate recovery procedure
- [ ] Validate cluster functionality
- [ ] Test application access
- [ ] Update monitoring and alerts
- [ ] Document incident and lessons learned

### Storage Failure Recovery Checklist
- [ ] Assess storage system status
- [ ] Check PV and PVC status
- [ ] Verify backup availability
- [ ] Execute storage recovery
- [ ] Restore data from backups if needed
- [ ] Validate data integrity
- [ ] Test application functionality
- [ ] Monitor for recurring issues

## Emergency Contacts and Resources

### Internal Resources
- **Cluster Configuration**: `/Users/ARAJI/git/homelabs/microk8s-cluster/homelab-terraform-gitopos-infra/`
- **Backup Locations**: Azure Blob Storage `cnpg-backups-homelab`
- **Monitoring**: Prometheus/Grafana dashboards

### External Resources
- **MicroK8s Documentation**: https://microk8s.io/docs
- **CNPG Documentation**: https://cloudnative-pg.io/documentation/
- **Kubernetes Troubleshooting**: https://kubernetes.io/docs/tasks/debug-application-cluster/

### Recovery Scripts
- **Emergency cleanup**: `/scripts/emergency-storage-cleanup.sh`
- **Node recovery**: `/scripts/node-recovery.sh`
- **Database recovery**: `/scripts/database-emergency-recovery.sh`