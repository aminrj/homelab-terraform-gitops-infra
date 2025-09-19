kubeconfig            = "~/.kube/microk8s-config"
kube_context          = "microk8s"
# default_data_path     = "/mnt/longhorn"
metallb_address_range = "10.0.30.200-10.0.30.220"
kubelet_root_dir      = "/var/snap/microk8s/common/var/lib/kubelet"
target_cluster_server = "https://kubernetes.default.svc"
namespace             = "cnpg"

ui_service_type = "LoadBalancer"

pg_storage_class = "microk8s-hostpath"
storage_class = "microk8s-hostpath"

slack_webhook_url = "https://hooks.slack.com/services/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"
