argocd_namespace = "argocd"
# kubeconfig = "~/.kube/config"
kubeconfig = "~/.kube/microk8s-config"
kube_context = "microk8s"
cloudflare_api_token = ""
target_cluster_server = "https://kubernetes.default.svc"
metallb_address_range = "10.0.30.200-10.0.30.220"
storage_class = "longhorn"
use_longhorn_storage = false

# Longhorn
default_data_path = "/mnt/longhorn"
kubelet_root_dir  = "/var/snap/microk8s/common/var/lib/kubelet"
ui_service_type   = "LoadBalancer"

