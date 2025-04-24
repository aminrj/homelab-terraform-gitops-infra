# Infrastructure GitOps Repository

## Some manual steps that need to be handled first

1. Bootstrap ESO Credential Secret:

```bash
kubectl create ns external-secrets

kubectl create secret generic azure-creds \
  -n external-secrets \
  --from-literal=client-id="$(terraform output -raw client_id)" \
  --from-literal=client-secret="$(terraform output -raw client_secret)"
```
