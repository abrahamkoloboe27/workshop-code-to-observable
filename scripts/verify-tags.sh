#!/usr/bin/env bash
# Critere d'acceptation executable : verifie que chaque tag est bien dans l'etat annonce.
# Chaque tag est teste dans un worktree temporaire, avec son propre projet Compose
# et des ports decales, pour ne rien casser de ta stack en cours.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
WORK=$(mktemp -d)
FAILURES=0
REBUILD_MAX=${REBUILD_MAX:-15}        # secondes : plafond du rebuild corrige (etage 3)
REBUILD_GAP_MIN=${REBUILD_GAP_MIN:-20} # secondes : ecart minimal exige entre step-02 et step-03
RESET_CYCLES=${RESET_CYCLES:-5}  # cycles down -v + up a l'etage 4

VERIFY_DB_PORT=5450
export APP_PORT=8100
export POSTGRES_HOST_PORT=${VERIFY_DB_PORT}
export PROMETHEUS_PORT=9190
export GRAFANA_PORT=3100
export POSTGRES_USER=workshop
export POSTGRES_PASSWORD=workshop-demo-password
export POSTGRES_DB=workshop

TEST_DSN="postgresql://workshop:workshop-demo-password@localhost:5451/workshop"

pass() { echo "    ✔ $1"; }
fail() { echo "    ✘ $1"; FAILURES=$((FAILURES + 1)); }
head2() { echo ""; echo "== $1 =="; }

cleanup() {
  echo ""
  echo "-- nettoyage --"
  for tag in step-00 step-01 step-02 step-03 step-04 step-05; do
    (cd "${WORK}/${tag}" 2>/dev/null && docker compose -p "wkv-${tag}" down -v --remove-orphans >/dev/null 2>&1)
    git -C "${REPO_ROOT}" worktree remove --force "${WORK}/${tag}" >/dev/null 2>&1
  done
  docker rm -f wkv-pytest-db >/dev/null 2>&1
  rm -rf "${WORK}"
  git -C "${REPO_ROOT}" worktree prune >/dev/null 2>&1
}
trap cleanup EXIT

# --- outillage Python partage -------------------------------------------------
PY="${REPO_ROOT}/.venv/bin/python"
if [ ! -x "${PY}" ]; then
  echo "-> creation d'un environnement Python temporaire"
  python3 -m venv "${WORK}/venv" >/dev/null
  PY="${WORK}/venv/bin/python"
  "${PY}" -m pip install -q -r "${REPO_ROOT}/requirements-dev.txt"
fi
RUFF="$(dirname "${PY}")/ruff"

# --- base de donnees dediee aux tests unitaires -------------------------------
echo "-> base de donnees de verification sur le port 5451"
docker rm -f wkv-pytest-db >/dev/null 2>&1
docker run -d --name wkv-pytest-db \
  -e POSTGRES_USER=workshop -e POSTGRES_PASSWORD=workshop-demo-password -e POSTGRES_DB=workshop \
  -p 5451:5432 \
  -v "${REPO_ROOT}/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  postgres:17-alpine >/dev/null
# Attente sur le port TCP : pendant le chargement de db/init.sql, Postgres
# n'ecoute que sur la socket locale. pg_isready mentirait ici.
for _ in $(seq 1 60); do
  "${PY}" -c "
import sys, psycopg
try:
    psycopg.connect('${TEST_DSN}', connect_timeout=2).close()
except Exception:
    sys.exit(1)" >/dev/null 2>&1 && break
  sleep 2
done

# --- worktrees ----------------------------------------------------------------
for tag in step-00 step-01 step-02 step-03 step-04 step-05; do
  git -C "${REPO_ROOT}" worktree add -q --detach "${WORK}/${tag}" "${tag}" || {
    echo "ERREUR : impossible de creer le worktree pour ${tag}"; exit 1; }
  cp -R "${REPO_ROOT}/wheels" "${WORK}/${tag}/wheels" 2>/dev/null || true
done

run_pytest() { (cd "${WORK}/$1" && DATABASE_URL="${TEST_DSN}" "${PY}" -m pytest -q >/dev/null 2>&1); }
run_ruff()   { (cd "${WORK}/$1" && "${RUFF}" check . >/dev/null 2>&1); }

wait_http() { # url attempts
  for _ in $(seq 1 "${2:-30}"); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$1" 2>/dev/null)" = "200" ] && return 0
    sleep 2
  done
  return 1
}

# ============================================================== step-00
head2 "step-00 — etat de depart"
run_pytest step-00 && fail "pytest devrait echouer" || pass "pytest echoue (le test rouge du depart)"
run_ruff step-00   && fail "ruff devrait echouer"   || pass "ruff echoue (import inutilise)"
grep -q 'ruff check . || true' "${WORK}/step-00/.github/workflows/ci.yml" \
  && pass "le workflow contient bien '|| true'" || fail "le workflow ne contient pas '|| true'"
grep -q 'workshop-app' "${WORK}/step-00/observability/prometheus.yml" \
  && fail "prometheus.yml ne devrait pas avoir de job applicatif" \
  || pass "prometheus.yml n'a pas de job applicatif"

# ============================================================== step-01
head2 "step-01 — la route /orders existe"
run_pytest step-01 && pass "pytest passe" || fail "pytest devrait passer"
run_ruff step-01   && fail "ruff devrait encore echouer" || pass "ruff echoue toujours (import inutilise)"

# ============================================================== step-02
head2 "step-02 — la CI dit la verite"
run_ruff step-02 && pass "ruff passe" || fail "ruff devrait passer"
grep -q '|| true' "${WORK}/step-02/.github/workflows/ci.yml" \
  && fail "le workflow contient encore '|| true'" || pass "le workflow ne contient plus '|| true'"

# ============================================================== step-03
# Le rebuild se mesure des DEUX cotes : sans les deux chiffres, l'ecart annonce
# par le brief (au moins 20 s) n'est verifie par rien.
measure_rebuild() { # $1 = tag ; imprime la duree en secondes sur stdout
  local tag="$1" img="wkv-app:$1"
  (cd "${WORK}/${tag}" && docker build -q -t "${img}" . >/dev/null 2>&1) || { echo "-1"; return; }
  echo "# rebuild probe $(date +%s)" >> "${WORK}/${tag}/app/routers/orders.py"
  local t0
  t0=$(date +%s)
  (cd "${WORK}/${tag}" && docker build -q -t "${img}" . >/dev/null 2>&1)
  echo $(( $(date +%s) - t0 ))
  git -C "${WORK}/${tag}" checkout -- app/routers/orders.py
}

head2 "step-03 — l'image"
IMG=wkv-app:step-03
if (cd "${WORK}/step-03" && docker build -q -t "${IMG}" . >/dev/null 2>&1); then
  pass "l'image se construit"
  uid=$(docker run --rm "${IMG}" id -u 2>/dev/null)
  [ "${uid}" != "0" ] && pass "le conteneur ne tourne pas en root (uid=${uid})" \
                      || fail "le conteneur tourne en root"

  rebuild_broken=$(measure_rebuild step-02)
  rebuild_fixed=$(measure_rebuild step-03)
  gap=$(( rebuild_broken - rebuild_fixed ))
  echo "    step-02 (Dockerfile casse)  : ${rebuild_broken}s"
  echo "    step-03 (Dockerfile corrige): ${rebuild_fixed}s"
  [ "${rebuild_fixed}" -le "${REBUILD_MAX}" ] \
    && pass "rebuild corrige : ${rebuild_fixed}s (plafond ${REBUILD_MAX}s)" \
    || fail "rebuild corrige trop lent : ${rebuild_fixed}s (plafond ${REBUILD_MAX}s)"
  [ "${gap}" -ge "${REBUILD_GAP_MIN}" ] \
    && pass "ecart casse/corrige : ${gap}s (minimum ${REBUILD_GAP_MIN}s)" \
    || fail "ecart casse/corrige insuffisant : ${gap}s (minimum ${REBUILD_GAP_MIN}s)"
else
  fail "l'image ne se construit pas"
fi

# ============================================================== step-04
head2 "step-04 — ${RESET_CYCLES} demarrages a froid consecutifs"
ok_cycles=0
for i in $(seq 1 "${RESET_CYCLES}"); do
  (cd "${WORK}/step-04" && docker compose -p wkv-step-04 down -v --remove-orphans >/dev/null 2>&1)
  # On attend que le PROCESSUS soit vivant (/health), puis on frappe la base (/orders).
  # C'est exactement la fenetre ou la course au demarrage se produit.
  if (cd "${WORK}/step-04" && docker compose -p wkv-step-04 up -d --build >/dev/null 2>&1) \
     && wait_http "http://localhost:${APP_PORT}/health" 15 \
     && [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://localhost:${APP_PORT}/orders")" = "200" ]; then
    ok_cycles=$((ok_cycles + 1)); echo "    cycle ${i} : ok"
  else
    echo "    cycle ${i} : ECHEC"
  fi
done
(cd "${WORK}/step-04" && docker compose -p wkv-step-04 down -v --remove-orphans >/dev/null 2>&1)
[ "${ok_cycles}" -eq "${RESET_CYCLES}" ] \
  && pass "${ok_cycles}/${RESET_CYCLES} cycles reussis" \
  || fail "${ok_cycles}/${RESET_CYCLES} cycles reussis"

# ============================================================== step-05
head2 "step-05 — Prometheus scrape l'application"
if (cd "${WORK}/step-05" && docker compose -p wkv-step-05 up -d --build >/dev/null 2>&1) \
   && wait_http "http://localhost:${APP_PORT}/health" 30 \
   && wait_http "http://localhost:${APP_PORT}/orders" 30; then
  TOTAL=50 APP_PORT="${APP_PORT}" bash "${WORK}/step-05/scripts/load.sh" >/dev/null 2>&1
  value=""
  for _ in $(seq 1 15); do
    value=$(curl -s "http://localhost:${PROMETHEUS_PORT}/api/v1/query?query=orders_requests_total" \
            | "${PY}" -c 'import json,sys;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else "")' 2>/dev/null)
    [ -n "${value}" ] && [ "${value}" != "0" ] && break
    sleep 2
  done
  if [ -n "${value}" ] && [ "${value}" != "0" ]; then
    pass "l'API Prometheus renvoie orders_requests_total = ${value}"
  else
    fail "orders_requests_total absent ou nul cote Prometheus"
  fi
else
  fail "la stack step-05 n'a pas demarre"
fi
(cd "${WORK}/step-05" && docker compose -p wkv-step-05 down -v --remove-orphans >/dev/null 2>&1)

# ============================================================== resume
echo ""
if [ "${FAILURES}" -eq 0 ]; then
  echo "TOUS LES TAGS SONT CONFORMES."
else
  echo "${FAILURES} assertion(s) en echec."
fi
exit $(( FAILURES > 0 ? 1 : 0 ))
