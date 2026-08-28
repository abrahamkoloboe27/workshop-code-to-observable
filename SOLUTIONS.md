# Solutions

Chaque bloc est replié. Ouvre-le quand tu es bloqué, ou après coup pour comparer.
Le *pourquoi* compte plus que le *quoi taper*.

---

<details>
<summary><b>Étage 1 — le test rouge : écrire <code>GET /orders</code></b></summary>

Crée `app/routers/orders.py` :

```python
from fastapi import APIRouter, Request

from app.db import fetch_all
from app.metrics import ORDERS_REQUESTS

router = APIRouter(tags=["orders"])

QUERY = "SELECT id, customer, amount, status FROM orders ORDER BY id LIMIT 50"


@router.get("/orders")
async def list_orders(request: Request) -> list[dict]:
    ORDERS_REQUESTS.inc()
    return await fetch_all(request.app.state.pool, QUERY)
```

Puis monte le router dans `app/main.py` :

```diff
-from app.routers import health, items
+from app.routers import health, items, orders
...
     app.include_router(items.router)
+    app.include_router(orders.router)
```

**Pourquoi ça compte.** Le compteur `orders_requests_total` n'est pas un détail cosmétique :
c'est la seule chose qui reliera, à l'étage 5, une ligne de code métier à une courbe sur un
écran. On instrumente au moment où on écrit la route, pas trois semaines plus tard quand
l'incident est déjà en cours.

</details>

---

<details>
<summary><b>Étage 2 — la CI : le badge qui ment</b></summary>

Dans `.github/workflows/ci.yml` :

```diff
       - name: Ruff
-        run: ruff check . || true
+        run: ruff check .
```

Pousse. **La CI passe au rouge** — c'est le but : elle dit enfin la vérité. Le lint échoue sur
un import inutilisé présent depuis le tout premier commit. Dans `app/main.py` :

```diff
-import json
 import time
```

Pousse à nouveau. Vert.

**Pourquoi ça compte.** `|| true` transforme une étape de vérification en décoration. Le job
réussit, le badge est vert, et personne ne regarde les logs. Une CI qui ne peut pas échouer ne
vérifie rien — elle coûte du temps de calcul pour produire une fausse assurance. Les deux
pushes que tu viens de faire, avec l'attente entre les deux, c'est aussi la leçon : une boucle
de feedback lente est un coût réel, et c'est pour ça qu'on lance le lint en local avant.

</details>

---

<details>
<summary><b>Étage 3 — l'image : le rebuild qui n'en finit pas</b></summary>

`Dockerfile`, avant :

```dockerfile
COPY . .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r app/requirements.txt
```

après :

```dockerfile
COPY app/requirements.txt ./app/requirements.txt
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r app/requirements.txt

COPY app/ ./app/

RUN useradd --create-home --uid 10001 appuser
USER appuser
```

Mesure : `make build`, change une ligne dans `app/routers/orders.py`, `make build` à nouveau.

Note au passage : `.dockerignore` n'exclut pas `wheels/`. Avec `COPY . .`, les wheels sont donc
recopiées *une deuxième fois* dans l'image, en plus du `COPY wheels/ /wheels/` qui les y a déjà
mises. Le défaut ne coûte pas que du temps : il gonfle aussi l'image. Le `COPY app/ ./app/` de
la version corrigée ne copie que ce dont le conteneur a besoin.

**Pourquoi ça compte.** Docker met en cache chaque instruction, et invalide tout ce qui suit
la première couche modifiée. Avec `COPY . .` en premier, la moindre virgule change le code,
donc invalide la couche, donc réinstalle toutes les dépendances. En copiant d'abord le seul
fichier dont dépend l'installation, la couche lourde ne se reconstruit que lorsque les
dépendances changent réellement. Le `USER` non privilégié n'a rien à voir avec la vitesse :
c'est simplement qu'un processus web n'a aucune raison d'être root dans son conteneur.

</details>

---

<details>
<summary><b>Étage 4 — la stack : la course au démarrage</b></summary>

`docker-compose.yml` :

```diff
   db:
     image: postgres:17-alpine
+    healthcheck:
+      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-workshop} -d ${POSTGRES_DB:-workshop}"]
+      interval: 2s
+      timeout: 3s
+      retries: 30
+      start_period: 5s

   app:
-    depends_on:
-      - db
+    depends_on:
+      db:
+        condition: service_healthy
```

**Pourquoi ça compte.** `depends_on` seul ne garantit que l'**ordre de démarrage des
conteneurs**, pas la disponibilité du service à l'intérieur. Postgres accepte des connexions
plusieurs secondes après que son conteneur est « démarré » — le temps d'initialiser le cluster
et de charger `db/init.sql`. D'où un échec **intermittent** : ça marche sur ta machine, ça
casse en CI, ou l'inverse. C'est exactement pourquoi `/health` et `/ready` sont deux routes
distinctes : pendant cette fenêtre, le processus est bien vivant (`/health` → 200) mais
incapable de servir (`/ready` → 503). Confondre les deux, c'est faire redémarrer en boucle un
service qui n'avait besoin que d'attendre.

</details>

---

<details>
<summary><b>Étage 5 — l'observabilité : le panel vide</b></summary>

`observability/prometheus.yml` :

```diff
 scrape_configs:
   - job_name: prometheus
     static_configs:
       - targets: ["localhost:9090"]
+
+  - job_name: workshop-app
+    metrics_path: /metrics
+    static_configs:
+      - targets: ["app:8000"]
```

Puis `docker compose restart prometheus` et `make load`.

**Pourquoi ça compte.** Exposer `/metrics` ne suffit pas : Prometheus fonctionne en *pull*,
il ne découvre rien tout seul. Une application parfaitement instrumentée dont personne ne
scrape l'endpoint produit exactement zéro donnée. Le panel `up{job="workshop-app"}` est là
pour ça — il ne mesure pas ton application, il mesure la chaîne de collecte elle-même. Quand
un dashboard est vide, la première question n'est jamais « la métrique existe-t-elle ? » mais
« la cible est-elle scrapée ? ».

</details>

---

<details>
<summary><b>Le rattrapage n'a pas supprimé mon fichier</b></summary>

`make catchup STEP=N` fait `git checkout step-0N -- .` : il écrase et restaure des fichiers,
mais il ne **supprime** rien. Si tu as *committé* un fichier qui n'existe pas à l'étape visée —
typiquement `app/routers/orders.py` quand tu reviens à `step-00` — il reste sur ton disque.

Supprime-le à la main :

```bash
git rm app/routers/orders.py
```

Ou repars propre sur l'état exact d'une étape, en gardant ta branche :

```bash
git stash push -u -m "mon travail"
git checkout step-0N -- .
git clean -fd            # supprime les fichiers non suivis ajoutes depuis
```

</details>
