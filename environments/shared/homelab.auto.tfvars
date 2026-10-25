# Non-secret settings for the MicroK8s cluster built by homelab-foundation (2026-10-25).
# Secrets come from Key Vault through the Makefile (TF_VAR_*), never from a file.
kubeconfig            = "~/.kube/microk8s-tunnel" # `make kube-tunnel` in homelab-foundation until Tailscale (B8)
kube_context          = "microk8s"
kubelet_root_dir      = "/var/snap/microk8s/common/var/lib/kubelet"
target_cluster_server = "https://kubernetes.default.svc"
metallb_address_range = "10.0.30.200-10.0.30.220" # homelab-foundation inventory: segments.services.reserved.metallb
storage_class         = "microk8s-hostpath"
pg_storage_class      = "microk8s-hostpath"
enable_external_dns   = false
