"""One-time sign-in for the demo user; caches a refreshable token in .out/ for the tests.

Two prompts:
1. Consent to the gateway app's downstream permissions (Azure Databricks, Microsoft Graph). APIM's
   On-Behalf-Of exchange needs this grant; without it OBO fails with AADSTS65001.
2. Sign in through the client app for the gateway scopes (pre-authorized, so no prompt for those).
"""

import sys
from pathlib import Path

import msal

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests.helpers import DATABRICKS_RESOURCE, claims, tf_outputs, user_token  # noqa: E402

out = tf_outputs()
gateway = msal.PublicClientApplication(
    out["gateway_app_id"], authority=f"https://login.microsoftonline.com/{out['tenant_id']}"
)
# A token request may name one resource; the others are consented in the same prompt.
result = gateway.acquire_token_interactive(
    [f"{DATABRICKS_RESOURCE}/user_impersonation"],
    extra_scopes_to_consent=[
        "https://graph.microsoft.com/User.Read",
        "https://graph.microsoft.com/User.ReadBasic.All",
    ],
    prompt="consent",
)
if "access_token" not in result:
    sys.exit(f"Consent to the gateway app failed: {result.get('error_description')}")

c = claims(user_token(interactive=True))
print(f"Signed in as {c.get('upn') or c.get('preferred_username') or c['oid']}, scopes: {c.get('scp')}")
