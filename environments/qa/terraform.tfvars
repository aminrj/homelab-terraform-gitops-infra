argocd_namespace = "argocd"
kubeconfig = "~/.kube/microk8s-config"
kube_context = "microk8s"
# cloudflare_api_token = ""
target_cluster_server = "https://kubernetes.default.svc"
metallb_address_range = "10.0.30.200-10.0.30.220"
pg_storage_class = "cnpg-longhorn"
storage_class = "longhorn"
use_longhorn_storage = true
pg_superuser_secret = "cnpg-superuser-qa"

# Longhorn
default_data_path = "/mnt/longhorn"
kubelet_root_dir  = "/var/snap/microk8s/common/var/lib/kubelet"
ui_service_type   = "LoadBalancer"

