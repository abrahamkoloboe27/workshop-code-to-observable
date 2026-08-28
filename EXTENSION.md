# Extension — pour aller plus loin

Cette branche part de l'état final du workshop et ajoute trois choses qui n'avaient pas leur
place dans les 60 minutes.

## Deux règles d'alerte

`observability/alerts.yml`, chargé par Prometheus via `rule_files`. Visible dans l'onglet
**Alerts** de Prometheus (http://localhost:9090/alerts).

- `AppTargetDown` — `up{job="workshop-app"} == 0` pendant 1 minute. C'est l'alerte qui
  détecte le défaut de l'étage 5 : elle surveille la collecte, pas l'application.
- `OrdersTrafficStalled` — plus aucune requête sur `/orders` pendant 5 minutes. Volontairement
  ambiguë : une panne et un dimanche matin produisent le même signal. Une alerte sur l'absence
  de trafic n'a de sens qu'avec un seuil calé sur ton trafic réel.

Il n'y a pas d'Alertmanager ici : les règles s'évaluent et se voient, elles ne notifient
personne. C'est l'étape suivante.

## Exporter Postgres

`postgres-exporter` expose les métriques de la base (connexions, transactions, taille) sur
`:9187`, scrapé par le job `postgres`. La base cesse d'être une boîte noire à côté de
l'application.

Essaie : `pg_stat_database_numbackends`, `pg_stat_database_xact_commit`.

## Reverse proxy Caddy

`observability/Caddyfile` place l'application et Grafana derrière une seule entrée, sur le
port 8080 :

- `http://localhost:8080/orders` → l'application
- `http://localhost:8080/grafana/` → Grafana

C'est la forme minimale de ce qu'un ingress fait en production. Il est ici, et pas dans le
parcours principal, parce qu'il coûte une image de plus et un fichier de configuration que
personne ne lit pendant un atelier.
