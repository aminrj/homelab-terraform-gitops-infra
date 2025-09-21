variable "kubeconfig" {
  description = "Path to kubeconfig file"
  type        = string
}

variable "git_repo_url" {
  description = "Git repository URL for GitOps"
  type        = string
  default     = "https://github.com/aminrj/homelab-terraform-gitops-infra.git"
}

variable "git_revision" {
  description = "Git revision/branch to track"
  type        = string
  default     = "main"
}