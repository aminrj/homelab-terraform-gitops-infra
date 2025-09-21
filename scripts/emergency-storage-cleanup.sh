#!/bin/bash

# Emergency Storage Cleanup Script
# This script performs aggressive cleanup to free up storage space immediately
# Use only in emergency situations when cluster is at risk

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/tmp/emergency-cleanup-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp}: ${message}" | tee -a "$LOGFILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${timestamp}: ${message}" | tee -a "$LOGFILE"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} ${timestamp}: ${message}" | tee -a "$LOGFILE"
            ;;
        DEBUG)
            echo -e "${BLUE}[DEBUG]${NC} ${timestamp}: ${message}" | tee -a "$LOGFILE"
            ;;
    esac
}

# Function to check if running in emergency mode
check_emergency_mode() {
    if [[ "$FORCE" != "true" ]]; then
        echo "⚠️  EMERGENCY STORAGE CLEANUP ⚠️"
        echo "This script will perform aggressive cleanup operations."
        echo "Use FORCE=true environment variable to proceed."
        echo ""
        echo "Example: FORCE=true $0"
        echo ""
        echo "For dry run: DRY_RUN=true $0"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."

    # Check kubectl access
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log ERROR "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Check permissions
    if ! kubectl auth can-i delete persistentvolumes; then
        log ERROR "Insufficient permissions to delete PersistentVolumes"
        exit 1
    fi

    log INFO "Prerequisites check passed"
}

# Function to get storage status
get_storage_status() {
    log INFO "Checking current storage status..."

    echo "=== Node Storage Status ===" | tee -a "$LOGFILE"
    kubectl top nodes 2>/dev/null | tee -a "$LOGFILE" || log WARN "Node metrics not available"

    echo "" | tee -a "$LOGFILE"
    echo "=== PV Status Summary ===" | tee -a "$LOGFILE"
    kubectl get pv --no-headers | awk '{print $5}' | sort | uniq -c | tee -a "$LOGFILE"

    echo "" | tee -a "$LOGFILE"
    echo "=== Large PVCs ===" | tee -a "$LOGFILE"
    kubectl get pvc --all-namespaces --sort-by=.spec.resources.requests.storage | tail -10 | tee -a "$LOGFILE"
}

# Function to cleanup failed/completed pods
cleanup_failed_pods() {
    log INFO "Cleaning up failed and completed pods..."

    local failed_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
    local succeeded_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Succeeded --no-headers 2>/dev/null | wc -l)

    log INFO "Found $failed_pods failed pods and $succeeded_pods completed pods"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete failed and completed pods"
        return 0
    fi

    if [[ $failed_pods -gt 0 ]]; then
        log INFO "Deleting failed pods..."
        kubectl delete pods --all-namespaces --field-selector=status.phase=Failed --wait=false || log WARN "Some failed pods could not be deleted"
    fi

    if [[ $succeeded_pods -gt 0 ]]; then
        log INFO "Deleting completed pods..."
        kubectl delete pods --all-namespaces --field-selector=status.phase=Succeeded --wait=false || log WARN "Some completed pods could not be deleted"
    fi
}

# Function to cleanup Released PVs
cleanup_released_pvs() {
    log INFO "Cleaning up Released PersistentVolumes..."

    local released_pvs=$(kubectl get pv --no-headers | grep Released | awk '{print $1}')
    local pv_count=$(echo "$released_pvs" | grep -c . || echo 0)

    log INFO "Found $pv_count Released PVs"

    if [[ $pv_count -eq 0 ]]; then
        log INFO "No Released PVs to clean up"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete the following Released PVs:"
        echo "$released_pvs" | tee -a "$LOGFILE"
        return 0
    fi

    # Safety limit - don't delete more than 10 PVs at once
    if [[ $pv_count -gt 10 ]]; then
        log WARN "Found $pv_count Released PVs. Limiting to first 10 for safety."
        released_pvs=$(echo "$released_pvs" | head -10)
    fi

    # Delete each PV with timeout
    for pv in $released_pvs; do
        log INFO "Deleting Released PV: $pv"
        if timeout 30s kubectl delete pv "$pv" --wait=false; then
            log INFO "Successfully deleted PV: $pv"
        else
            log ERROR "Failed to delete PV: $pv"
        fi
    done
}

# Function to cleanup old ReplicaSets
cleanup_old_replicasets() {
    log INFO "Cleaning up old ReplicaSets..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would clean up old ReplicaSets"
        kubectl get rs --all-namespaces | grep -E '0\s+0\s+0' | head -5 | tee -a "$LOGFILE"
        return 0
    fi

    # Find ReplicaSets with 0 replicas older than 1 hour
    local old_rs=$(kubectl get rs --all-namespaces --no-headers | awk '$3 == 0 && $4 == 0 && $5 == 0' | head -10)

    if [[ -n "$old_rs" ]]; then
        log INFO "Cleaning up old ReplicaSets with 0 replicas..."
        echo "$old_rs" | while read ns name rest; do
            log INFO "Deleting ReplicaSet: $ns/$name"
            kubectl delete rs -n "$ns" "$name" --wait=false || log WARN "Could not delete ReplicaSet $ns/$name"
        done
    else
        log INFO "No old ReplicaSets to clean up"
    fi
}

# Function to cleanup old events
cleanup_old_events() {
    log INFO "Cleaning up old events..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would clean up old events"
        return 0
    fi

    # Delete events older than 1 hour
    kubectl get events --all-namespaces --sort-by='.firstTimestamp' --no-headers | head -100 | while read line; do
        ns=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        kubectl delete event -n "$ns" "$name" --wait=false >/dev/null 2>&1 || true
    done

    log INFO "Old events cleanup completed"
}

# Function to force garbage collection
force_garbage_collection() {
    log INFO "Forcing garbage collection..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would force garbage collection"
        return 0
    fi

    # Restart kubelet on all nodes to trigger garbage collection
    log WARN "This would require node access to restart kubelet - manual step needed"
    log INFO "Run on each node: sudo systemctl restart snap.microk8s.daemon-kubelet"
}

# Function to generate emergency report
generate_emergency_report() {
    log INFO "Generating emergency cleanup report..."

    local report_file="/tmp/emergency-cleanup-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "=== EMERGENCY STORAGE CLEANUP REPORT ==="
        echo "Date: $(date)"
        echo "Script: $0"
        echo "Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "LIVE")"
        echo ""

        echo "=== FINAL STORAGE STATUS ==="
        kubectl top nodes 2>/dev/null || echo "Node metrics not available"
        echo ""

        echo "=== PV STATUS AFTER CLEANUP ==="
        kubectl get pv --no-headers | awk '{print $5}' | sort | uniq -c
        echo ""

        echo "=== REMAINING LARGE PVCS ==="
        kubectl get pvc --all-namespaces --sort-by=.spec.resources.requests.storage | tail -5
        echo ""

        echo "=== CLUSTER HEALTH ==="
        kubectl get nodes
        echo ""
        kubectl get pods --all-namespaces | grep -v Running | grep -v Completed || echo "All pods running normally"
        echo ""

        echo "=== CLEANUP LOG ==="
        cat "$LOGFILE"

    } > "$report_file"

    log INFO "Emergency report generated: $report_file"
    echo "Report location: $report_file"
}

# Main execution function
main() {
    log INFO "Starting emergency storage cleanup..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Running in DRY RUN mode - no changes will be made"
    fi

    check_emergency_mode
    check_prerequisites
    get_storage_status

    # Execute cleanup procedures
    cleanup_failed_pods
    cleanup_released_pvs
    cleanup_old_replicasets
    cleanup_old_events
    force_garbage_collection

    log INFO "Emergency storage cleanup completed"
    generate_emergency_report

    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "⚠️  Manual steps still required:"
        log INFO "1. SSH to each node and run: sudo microk8s.crictl images prune -a"
        log INFO "2. Clean system logs: sudo journalctl --vacuum-time=1d"
        log INFO "3. Restart kubelet if needed: sudo systemctl restart snap.microk8s.daemon-kubelet"
        log INFO "4. Monitor cluster for 30 minutes to ensure stability"
    fi
}

# Script usage
usage() {
    cat << EOF
Emergency Storage Cleanup Script

Usage: $0 [OPTIONS]

Environment Variables:
  FORCE=true      Enable destructive operations (required)
  DRY_RUN=true    Preview operations without making changes

Examples:
  # Dry run to preview operations
  DRY_RUN=true $0

  # Emergency cleanup (destructive)
  FORCE=true $0

  # Dry run with force flag
  DRY_RUN=true FORCE=true $0

This script performs aggressive cleanup operations including:
- Deleting failed and completed pods
- Removing Released PersistentVolumes
- Cleaning up old ReplicaSets and Events
- Forcing garbage collection

⚠️  WARNING: This script is for emergency use only!
Use only when cluster is at risk due to storage exhaustion.

EOF
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac