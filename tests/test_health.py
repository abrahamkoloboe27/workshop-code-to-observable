def test_health_is_up(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_reaches_the_database(client):
    response = client.get("/ready")
    assert response.status_code == 200, (
        "GET /ready a repondu 503 : la base n'est pas joignable. "
        "Verifie que `make up` tourne."
    )


def test_metrics_are_exposed(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_request_duration_seconds" in response.text
