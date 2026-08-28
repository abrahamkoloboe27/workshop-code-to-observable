"""Le test rouge du depart. C'est lui qui ouvre le workshop.

Il decrit la route `GET /orders` que tu dois ecrire toi-meme (etage 1) :
elle lit la table `orders`, renvoie du JSON, et incremente le compteur
Prometheus `orders_requests_total`.
"""


def _orders_counter(metrics_text: str) -> float:
    for line in metrics_text.splitlines():
        if line.startswith("orders_requests_total "):
            return float(line.split()[1])
    return 0.0


def test_orders_returns_a_json_list(client):
    response = client.get("/orders")
    assert response.status_code == 200, (
        f"GET /orders a repondu {response.status_code}.\n"
        "La route n'existe pas encore : c'est le changement que tu ecris.\n"
        "Cree app/routers/orders.py, puis monte le router dans app/main.py.\n"
        "Regarde app/routers/items.py : c'est exactement le meme motif."
    )
    payload = response.json()
    assert isinstance(payload, list), "GET /orders doit renvoyer une liste JSON."
    assert payload, "La table `orders` est peuplee par db/init.sql : la liste ne doit pas etre vide."
    assert {"id", "customer", "amount", "status"} <= set(payload[0])
    assert len(payload) <= 50, (
        f"GET /orders a renvoye {len(payload)} elements.\n"
        "Un endpoint de liste se borne : sans LIMIT, la reponse grossit avec la table, "
        "la serialisation JSON et la memoire du processus avec elle. Le jour ou la table "
        "atteint le million de lignes, c'est une requete qui met l'API a genoux.\n"
        "Regarde le LIMIT de app/routers/items.py."
    )


def test_orders_increments_the_prometheus_counter(client):
    before = _orders_counter(client.get("/metrics").text)
    client.get("/orders")
    after = _orders_counter(client.get("/metrics").text)
    assert after == before + 1, (
        "Le compteur `orders_requests_total` n'a pas bouge.\n"
        "Incremente-le dans la route : c'est lui qui alimentera le dashboard "
        "Grafana a l'etage 5."
    )
