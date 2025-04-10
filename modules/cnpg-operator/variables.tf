variable "kubeconfig" {
  type        = string
}

variable "namespace" {
  type    = string
}

variable "use_longhorn_storage" {
  description = "Whether to create and use a special Longhorn StorageClass for cnpg"
  type    = bool
  default = false
}

