"""Post-provision Foundry setup (idempotent). Run after `make up`: `make foundry`.

Flow #2: creates the prompt agent `uga-databricks-agent`, whose model is a Databricks Foundation Model
reached through the `databricks-models` APIM connection (infra/foundry_byom.tf). Each run adds a new
agent version, so model or instruction changes here are picked up.
"""

from __future__ import annotations

import sys
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import AzureCliCredential

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests.helpers import tf_outputs  # noqa: E402

AGENT = "uga-databricks-agent"

out = tf_outputs()
model = f"{out['foundry_connection']}/{out['foundry_models'][0]}"

project = AIProjectClient(
    endpoint=out["foundry_project_endpoint"],
    credential=AzureCliCredential(tenant_id=out["tenant_id"]),
)
agent = project.agents.create_version(
    agent_name=AGENT,
    definition=PromptAgentDefinition(
        model=model,
        instructions=(
            "You are a helpful assistant. Your model runs on Azure Databricks and is reached through "
            "Azure API Management, authenticated as this Foundry project's managed identity."
        ),
    ),
    description="Flow #2: Foundry agent on a Databricks Foundation Model via APIM",
)
print(f"Agent {agent.name} version {agent.version} -> model {model}")
