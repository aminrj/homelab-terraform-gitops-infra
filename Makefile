# Cluster software for the MicroK8s cluster that homelab-foundation builds.
# Plan first, read it, then apply exactly that plan. State is in Azure (backend.hcl).
#
#   make shared-init       # once per machine (needs az login and environments/shared/backend.hcl)
#   make shared-plan       # writes shared.tfplan
#   make shared-apply      # applies shared.tfplan
#
# The cluster API must be reachable: Tailscale (homelab-foundation cutover.md B8), or
# `make kube-tunnel` there. Context `homelab` in ~/.kube/homelab either way.
# Never run the prod env from here: its state is still local on the Mac.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
-include .env
export
KEY_VAULT_NAME ?= $(shell sed -n 's/^KEY_VAULT_NAME=//p' ../homelab-foundation/.env 2>/dev/null)

SHARED := terraform -chdir=environments/shared
PLAN := shared.tfplan

# Optional secrets from Key Vault into TF_VAR_*; a missing secret leaves the variable's default.
define load_secrets
	for pair in cloudflare_api_token:gitops-cloudflare-api-token slack_webhook_url:gitops-slack-webhook-url; do \
	  v=$$(az keyvault secret show --vault-name "$(KEY_VAULT_NAME)" -n "$${pair#*:}" --query value -o tsv 2>/dev/null || true); \
	  [ -n "$$v" ] && export "TF_VAR_$${pair%%:*}=$$v"; \
	done; unset v;
endef

.PHONY: help shared-init shared-migrate-state shared-plan shared-apply db-backup grafana-admin-sync
help: ## List targets
	@grep -hE '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-22s %s\n", $$1, $$2}'

shared-init: ## Init the shared env against the Azure backend
	@test -f environments/shared/backend.hcl || { echo "copy environments/shared/backend.hcl.example to backend.hcl"; exit 1; }
	$(SHARED) init -backend-config=backend.hcl

shared-migrate-state: ## One time: push a local state file into the empty Azure backend (LOCAL_STATE=)
	@test -n "$(LOCAL_STATE)" || { echo "set LOCAL_STATE=~/homelab-state/gitops-shared/shared.tfstate"; exit 1; }
	@test -z "$$($(SHARED) state list 2>/dev/null)" || { echo "the backend already holds state: not overwriting it"; exit 1; }
	$(SHARED) state push $(LOCAL_STATE)
	$(SHARED) state list | wc -l | xargs echo "resources in the backend:"

shared-plan: ## Plan the shared env (saves shared.tfplan; ARGS=-replace=...)
	@test -n "$(KEY_VAULT_NAME)" || { echo "set KEY_VAULT_NAME (in .env)"; exit 1; }
	@$(load_secrets) $(SHARED) plan -out=$(PLAN) $(ARGS)

shared-apply: ## Apply exactly the saved plan
	@test -f environments/shared/$(PLAN) || { echo "run make shared-plan first"; exit 1; }
	$(SHARED) apply $(PLAN) && rm -f environments/shared/$(PLAN)

db-backup: ## On-demand CNPG backup of an app's database to Azure, waits for it (APP=n8n)
	@test -n "$(APP)" || { echo "set APP=<app>"; exit 1; }
	scripts/db-backup.sh $(APP)

grafana-admin-sync: ## Set Grafana's admin password from Key Vault (after it changes)
	scripts/grafana-admin-sync.sh
