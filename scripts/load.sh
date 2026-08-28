#!/usr/bin/env bash
# Envoie 500 requetes sur /orders pour faire monter la courbe du dashboard.
set -uo pipefail

PORT="${APP_PORT:-8000}"
URL="http://localhost:${PORT}/orders"
TOTAL="${TOTAL:-500}"

echo "-> ${TOTAL} requetes sur ${URL}"

ok=0
ko=0
for _ in $(seq 1 "${TOTAL}"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${URL}" || echo 000)
  if [ "${code}" = "200" ]; then
    ok=$((ok + 1))
  else
    ko=$((ko + 1))
  fi
done

echo "-> ${ok} reponses 200, ${ko} en echec"
if [ "${ok}" -eq 0 ]; then
  echo "   Aucune reponse 200 : la route /orders existe-t-elle, et la stack tourne-t-elle ?"
  exit 1
fi
echo "   Ouvre Grafana sur http://localhost:${GRAFANA_PORT:-3000} : la courbe doit monter."
