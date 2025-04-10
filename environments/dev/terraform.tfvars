argocd_namespace = "argocd"
kubeconfig = "~/.kube/config"
kube_context = "rancher-desktop"
target_cluster_server = "https://kubernetes.default.svc"
metallb_address_range = "192.168.5.240-192.168.5.250"
pg_storage_class = "local-path"
storage_class = "local-path"
use_longhorn_storage = false

# Longhorn
# default_data_path = "/mnt/longhorn"   # or any dev path
# kubelet_root_dir  = "/var/lib/kubelet"
# ui_service_type   = "ClusterIP"        # or "NodePort" if you prefer


app_name            = "eso-dev"
key_vault_name      = "hlab-keyvault-dev"
location            = "swedencentral"
resource_group_name = "homelab"
storage_account_name= "hldatabasedev"
