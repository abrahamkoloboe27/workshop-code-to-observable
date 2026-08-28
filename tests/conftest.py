import os

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture(scope="session")
def client():
    if not os.getenv("DATABASE_URL"):
        pytest.fail(
            "DATABASE_URL n'est pas defini.\n"
            "Lance les tests avec `make test` : la cible demarre la base et "
            "positionne la variable pour toi."
        )
    with TestClient(create_app()) as test_client:
        yield test_client
