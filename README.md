# From Code to Observable

Tu vas suivre **un seul changement de code** — ajouter la route `GET /orders` — jusqu'à ce
qu'il soit observable en production. Cinq étages. À chaque étage, quelque chose bloque.

```
  ┌─ 5 ─ observabilité ── la courbe monte dans Grafana
  ├─ 4 ─ la stack ─────── tout démarre dans le bon ordre
  ├─ 3 ─ l'image ──────── le rebuild ne prend plus une éternité
  ├─ 2 ─ la CI ────────── le badge dit la vérité
  └─ 1 ─ ton poste ────── le test passe
```

Tu ne pars pas d'une page blanche : la stack est complète. Elle est aussi cassée, exprès.
Chaque étage contient exactement **un** défaut entre toi et l'étage suivant.

## La veille — ton ticket d'entrée

1. Forke ce dépôt, puis clone **ton fork**.
2. Lance :

   ```bash
   make preflight
   ```

3. Colle le bloc résumé final dans le canal du workshop.

Le preflight tire les images Docker et télécharge les dépendances Python en local. Le jour J,
plus rien ne passe par le réseau : la salle ne le supporterait pas.

## Le jour J

```bash
make test    # ton point de départ : un test rouge
make up      # la stack complète
make load    # 500 requêtes sur /orders
make down    # arrêter la stack, en gardant les données
make reset   # repartir de zéro : volumes supprimés, base rechargée
```

`make` sans argument liste les cibles. Toutes les commandes de la séance, étage par étage,
sont dans [`COMMANDS.md`](COMMANDS.md).

Ta CI vit dans l'onglet **Actions** de ton fork. C'est là que tu regarderas, à l'étage 2, si
le vert veut dire quelque chose.

## Si tu décroches

Personne ne reste bloqué. Pour te réaligner sur l'étape 3 :

```bash
make catchup STEP=3
```

Le script met ton travail de côté (`git stash`), remet **les fichiers** dans l'état de l'étape
demandée, et te dit où retrouver ce que tu avais commencé. Ta branche et tes commits ne bougent
pas. Ne fais jamais `git checkout step-03` toi-même.

`SOLUTIONS.md` est là depuis le début, et c'est voulu. Mieux vaut lire une réponse et avancer
que rester coincé.

## Ce que tu emportes

Un dépôt qui tient debout : un test qui échoue pour une bonne raison, une CI qui ne ment pas,
une image qui se reconstruit en quelques secondes, une stack qui attend ses dépendances, et un
compteur métier qu'on voit bouger.

Le tag `final` contient l'état complet et fonctionnel. La branche `extension` va plus loin :
règle d'alerting, exporter Postgres, reverse proxy.
