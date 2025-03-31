# Example usage in a Terraform deployment

```terraform
module "cnpg" {
  source      = "./modules/cloudnativepg"
  kubeconfig  = "~/.kube/config"
}
```
