TFVARS ?= sandbox.tfvars
TF      = terraform -chdir=infra
TENANT_ID             = $(shell awk -F'"' '/^tenant_id/{print $$2}' infra/$(TFVARS))
DATABRICKS_ACCOUNT_ID = $(shell awk -F'"' '/^databricks_account_id/{print $$2}' infra/$(TFVARS))
export ARM_TENANT_ID = $(TENANT_ID)

.PHONY: help whoami init plan up databricks foundry login test-feasibility test down

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

whoami: ## Check every credential is pinned to the right tenant
	TENANT_ID=$(TENANT_ID) DATABRICKS_ACCOUNT_ID=$(DATABRICKS_ACCOUNT_ID) scripts/whoami.sh

init:
	$(TF) init -input=false
	uv sync --extra foundry

plan: init ## Show what `make up` would change
	$(TF) plan -input=false -var-file=$(TFVARS)

up: init ## Deploy Azure, Entra, APIM, Foundry and the Databricks workspace (with UC metastore)
	$(TF) apply -input=false -var-file=$(TFVARS)

databricks: ## Post-provision: Unity Catalog connection + MCP service for the APIM Graph MCP
	uv run python databricks/setup.py

foundry: ## Post-provision: Foundry prompt agent on a Databricks model via APIM (flow #2)
	uv run python foundry/setup.py

login: ## Sign in once as the demo user (consent + token cache for the tests)
	uv run python scripts/login.py

test-feasibility: ## Phase 0: check each auth hop on its own
	uv run pytest -m feasibility

test: ## End-to-end checks for the three flows
	uv run pytest -m e2e

down: ## Destroy everything `make up` created
	$(TF) destroy -input=false -var-file=$(TFVARS)
