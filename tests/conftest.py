import pytest

from tests.helpers import DATABRICKS_RESOURCE, az_token, tf_outputs, user_token


@pytest.fixture(scope="session")
def out() -> dict:
    return tf_outputs()


@pytest.fixture(scope="session")
def databricks_token(out) -> str:
    """The signed-in user's Entra token for Azure Databricks (from the az CLI)."""
    return az_token(DATABRICKS_RESOURCE, out["tenant_id"])


@pytest.fixture(scope="session")
def gateway_token() -> str:
    """The signed-in user's Entra token for the APIM gateway API (from `make login`)."""
    return user_token()
