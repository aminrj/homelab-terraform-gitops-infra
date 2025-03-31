variable "metallb_address_range" {
  description = "Address range to use for MetalLB IP pool"
  type        = string
}

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}
