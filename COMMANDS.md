# Commandes du workshop

Toutes les commandes à taper, dans l'ordre.

Ce document ne contient **pas les corrections**. À chaque étage, tu as les commandes pour
constater le problème et pour vérifier que tu l'as résolu — le diagnostic, c'est toi.
Si tu bloques : `SOLUTIONS.md` est dans le dépôt depuis le début.

```
  ┌─ 5 ─ observabilité ── la courbe monte dans Grafana
  ├─ 4 ─ la stack ─────── tout démarre dans le bon ordre
  ├─ 3 ─ l'image ──────── le rebuild ne prend plus une éternité
  ├─ 2 ─ la CI ────────── le badge dit la vérité
  └─ 1 ─ ton poste ────── le test passe
```

---

## Étage 0 — le décollage

Tu travailles sur **ton fork**, cloné hier pendant le preflight.

```bash
cd workshop-code-to-observable
git status          # tu dois être sur main, propre
make                # liste toutes les cibles
```

Démarrer la stack complète :

```bash
make up
```

Vérifier que tout est debout :

```bash
curl -s localhost:8000/health
curl -s localhost:8000/items | head -c 200
```

Trois onglets à ouvrir maintenant et à garder ouverts toute la séance :

| Onglet | URL |
|---|---|
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090/targets |
| Tes Actions | l'onglet **Actions** de ton fork |

> Si `make up` échoue, ne débogue pas seul : lève ton post-it.

---

## Étage 1 — ton poste

**Objectif : `make test` passe au vert.**

```bash
make test
```

Deux tests échouent. Lis le message : il te dit exactement quoi construire.

Ta mission : écrire la route `GET /orders`. Elle lit la table `orders`, renvoie du JSON,
et incrémente le compteur Prometheus `orders_requests_total`.

Regarde `app/routers/items.py` : c'est le même motif, à un nom près.

Fichiers concernés : `app/routers/` et `app/main.py`.

Quand tu penses avoir fini :

```bash
make test
```

Objectif atteint quand les deux tests passent.

```bash
curl -s localhost:8000/orders | head -c 200
```

---

## Étage 2 — la CI

**Objectif : ton badge dit la vérité.**

Envoie ton travail :

```bash
git add -A
git commit -m "feat: add GET /orders"
git push
```

Va sur l'onglet **Actions** de ton fork. Regarde le badge.

Maintenant ouvre le job `lint` et lis sa sortie **en entier**.

```bash
make lint
```

Compare ce que dit ton terminal et ce que dit ton badge. Les deux sont censés parler
du même code.

Ta mission : faire en sorte que le badge cesse de mentir, puis rendre le code propre.

Fichiers concernés : `.github/workflows/ci.yml` et `app/main.py`.

Après chaque correction :

```bash
git add -A && git commit -m "ci: ..." && git push
```

Objectif atteint quand le badge est vert **et** que `make lint` passe en local.

> Chaque push prend 1 à 2 minutes côté GitHub. Ne reste pas à regarder la page tourner :
> on enchaîne sur l'étage 3 pendant ce temps.

---

## Étage 3 — l'image

**Objectif : reconstruire l'image après une modification de code prend quelques secondes.**

```bash
make build
```

Note la durée affichée à la fin.

Change une ligne dans ta route `/orders` — un commentaire suffit :

```bash
echo "# ligne de test" >> app/routers/orders.py
make build
```

Note la durée. Compare.

Ta mission : comprendre pourquoi une ligne de commentaire coûte aussi cher, et corriger.
Profites-en pour regarder sous quel utilisateur tourne le conteneur.

Fichier concerné : `Dockerfile`.

Pour vérifier :

```bash
make build                              # première fois après correction
echo "# encore" >> app/routers/orders.py
make build                              # doit être beaucoup plus rapide
docker compose run --rm app id -u       # doit renvoyer autre chose que 0
```

Nettoie tes lignes de test avant de continuer.

---

## Étage 4 — la stack

**Objectif : cinq démarrages à froid d'affilée, cinq succès.**

```bash
make reset
```

Puis, tout de suite, sans attendre :

```bash
curl -s -o /dev/null -w 'health : %{http_code}\n' localhost:8000/health
curl -s -o /dev/null -w 'ready  : %{http_code}\n' localhost:8000/ready
curl -s -o /dev/null -w 'orders : %{http_code}\n' localhost:8000/orders
```

Regarde bien les trois codes. Ils ne disent pas la même chose, et c'est tout le sujet.

```bash
docker compose ps
docker compose logs app | tail -20
```

Ta mission : faire en sorte que l'application ne démarre pas avant que sa base soit
réellement prête.

Fichier concerné : `docker-compose.yml`.

Pour vérifier, répète trois fois :

```bash
make reset && curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/orders
```

Objectif atteint quand tu obtiens `200` à chaque fois.

---

## Étage 5 — l'observabilité

**Objectif : voir monter la courbe de ton propre endpoint.**

Ton application expose bien ses métriques :

```bash
curl -s localhost:8000/metrics | grep orders_requests_total
```

Mais regarde Grafana : http://localhost:3000 — le panel est vide.

Et regarde qui Prometheus surveille réellement : http://localhost:9090/targets

Ta mission : relier les deux.

Fichier concerné : `observability/prometheus.yml`.

Après correction, recharge la configuration :

```bash
docker compose restart prometheus
```

Reviens sur http://localhost:9090/targets — ta cible doit apparaître en `UP`.

Puis fais monter la courbe :

```bash
make load
```

Objectif atteint quand la courbe bouge dans Grafana pendant que la commande tourne.

---

## Si tu décroches

Une seule commande, à n'importe quel moment :

```bash
make catchup STEP=3
```

Elle met ton travail de côté (`git stash`) et remet **tes fichiers** dans l'état de
l'étape demandée. Ta branche et tes commits ne bougent pas.

Ne fais jamais `git checkout step-03` toi-même.

Pour retrouver ce que tu avais commencé :

```bash
git stash list
git stash pop
```

---

## En cas de problème

**`make up` échoue avec un port déjà utilisé.** Change le port dans ton `.env`
(`APP_PORT`, `GRAFANA_PORT`, `PROMETHEUS_PORT`, `POSTGRES_HOST_PORT`), puis `make up`.

**`make build` dit que `wheels/` est vide.** Le preflight n'a pas été fait ou a échoué :

```bash
make wheels
```

**`make test` dit que l'environnement Python est absent.**

```bash
make venv
```

**L'onglet Actions ne montre aucun workflow.** GitHub les désactive sur un fork tant que
tu n'as pas cliqué le bandeau de confirmation. Va sur l'onglet Actions de ton fork et
clique dessus.

**Tout est cassé et tu ne sais plus où tu en es.**

```bash
make catchup STEP=<le dernier étage terminé>
```

---

## Tout arrêter, à la fin

```bash
make down    # arrête la stack, garde tes données
```

Pour repartir totalement de zéro :

```bash
make reset
```

---

## Ce que tu emportes

Ton fork, avec dedans :

- une route que tu as écrite et un test qui la couvre
- un pipeline CI qui ne ment plus
- une image qui se reconstruit en quelques secondes
- une stack qui attend ses dépendances au lieu d'espérer
- un compteur métier visible sur un dashboard

Le tag `final` contient l'état complet. La branche `extension` va plus loin :
règle d'alerting, exporter Postgres, reverse proxy.
