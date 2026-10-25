variable "key_vault_name" {
  type = string
}

variable "key_vault_resource_group" {
  type = string
}

variable "eso_client_id" {
  description = "Client ID of the ESO app registration (holds Key Vault Secrets User on the vault)"
  type        = string
}

variable "password_rotation_days" {
  type    = number
  default = 180
}

variable "repo_url" {
  type    = string
  default = "git@github.com:aminrj/homelab-terraform-gitops-infra.git"
}
