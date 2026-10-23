#!/usr/bin/env bash
# Print the tenant of every credential the build uses. All must be the sandbox tenant.
set -euo pipefail

TENANT_ID="${TENANT_ID:?set TENANT_ID}"
ACCOUNT_ID="${DATABRICKS_ACCOUNT_ID:?set DATABRICKS_ACCOUNT_ID}"

tid() { python3 -c 'import sys,json,base64; p=sys.stdin.read().split(".")[1]; p+="="*(-len(p)%4); print(json.loads(base64.urlsafe_b64decode(p))["tid"])'; }

for resource in https://management.azure.com/ 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d https://graph.microsoft.com; do
  got=$(az account get-access-token --tenant "$TENANT_ID" --resource "$resource" --query accessToken -o tsv | tid)
  printf '%-45s tid=%s %s\n' "$resource" "$got" "$([ "$got" = "$TENANT_ID" ] && echo OK || echo MISMATCH)"
done

DATABRICKS_HOST=https://accounts.azuredatabricks.net \
DATABRICKS_ACCOUNT_ID="$ACCOUNT_ID" \
DATABRICKS_AUTH_TYPE=azure-cli \
DATABRICKS_AZURE_TENANT_ID="$TENANT_ID" \
  databricks account metastores list -o json >/dev/null && echo "Databricks account $ACCOUNT_ID: OK"
