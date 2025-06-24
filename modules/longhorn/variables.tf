
variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}

variable "default_data_path" {
  type = string
}

variable "default_replica_count" {
  type    = number
  default = 2
}

variable "kubelet_root_dir" {
  type = string
}

variable "ui_service_type" {
  type    = string
  default = "LoadBalancer"
}

