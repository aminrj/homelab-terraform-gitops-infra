# Gitea

Private git server for the personal assistant (homelab-foundation `docs/assistant.md`): the agents
write only on branches and open pull requests; you review and merge. Revived 2026-10-27 on the
MicroK8s cluster; `DEPLOYMENT.md` and `AZURE-SECRETS.md` describe the old 2025 setup and are kept
for history only.

| | |
|---|---|
| URL | https://gitea.lab.aminrj.com (split DNS, Tailscale; nothing public) |
| Version | `gitea/gitea:1.26`, HTTPS only (no SSH), registration off, sign-in required, Actions off |
| Database | `databases/gitea` (CNPG `gitea-db-cnpg-v2`), backups to foundation's offsite account |
| Repos on disk | PVC `gitea-data` (microk8s-hostpath) |
| Off-site | `overlays/prod/offsite.yaml`: nightly age-encrypted git bundles of every repo to Azure Blob; `main` of opted-in repos pushed to private GitHub repos |
| Users and repos | homelab-foundation `assistant/gitea.yml` (`make assistant-gitea` there) |

Bootstrap, in order:

```bash
make gitea-secrets          # missing Key Vault secrets (db, secret key, internal token, admin password)
# merge to main: ArgoCD syncs databases/gitea and apps/gitea
make gitea-admin            # your admin user in the pod (password in Key Vault)
# sign in, create an all-scopes token, then in homelab-foundation:
make secret-set NAME=gitea-admin-token && make assistant-gitea ARGS=--yes
```

Restore a repo from the off-site copy:

```bash
az storage blob download --account-name hlabpvebknwkqcj -c gitea -n repos/<date>/amine_vault.bundle.age -f vault.bundle.age --auth-mode login
age -d -i <(az keyvault secret show --vault-name hlab-keyvault-prod -n foundation-backup-age-key --query value -o tsv) vault.bundle.age > vault.bundle
git clone vault.bundle vault
```
