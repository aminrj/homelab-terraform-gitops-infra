output "cnpg_namespace" {
  value = kubernetes_namespace.cnpg.metadata[0].name
}

output "cnpg_storage_class" {
  value = kubernetes_storage_class.cnpg_longhorn.metadata[0].name
}
