# modules/cnpg-cluster/variables.tf

variable "namespace" {
  type = string
}

variable "pg_cluster_name" {
  type = string
}

variable "pg_instance_count" {
  type = number
}

variable "pg_storage_class" {
  type = string
}

variable "pg_storage_size" {
  type = string
}

variable "pg_superuser_secret" {
  type = string
}

variable "pg_app_secret" {
  type = string
}

variable "pg_monitoring_enabled" {
  type    = bool
  default = true
}
