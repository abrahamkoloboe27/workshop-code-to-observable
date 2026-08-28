#!/usr/bin/env bash
# A lancer LA VEILLE du workshop, sur la machine que tu apporteras.
# Poste le bloc resume final dans le canal du workshop : c'est ton ticket d'entree.
set -uo pipefail

IMAGES=(python:3.12-slim postgres:17-alpine prom/prometheus:v3.13.0 grafana/grafana:13.1.0-slim)
UPSTREAM_PATTERN='denisakp/workshop-code-to-observable'
RESULTS=()
FAILURES=0

ok()   { echo "  ✔ $1"; RESULTS+=("✔ $1"); }
ko()   { echo "  ✘ $1"; RESULTS+=("✘ $1"); FAILURES=$((FAILURES + 1)); }
step() { echo ""; echo "$1"; }

echo "=============================================="
echo " Preflight — From Code to Observable"
echo "=============================================="

# ---------------------------------------------------------------- 1. Docker
step "1. Docker"
if command -v docker >/dev/null 2>&1; then
  ok "docker installe ($(docker --version | cut -d, -f1))"
  if docker info >/dev/null 2>&1; then
    ok "le demon Docker tourne"
  else
    ko "le demon Docker ne repond pas — lance Docker Desktop / OrbStack"
  fi
  if docker compose version >/dev/null 2>&1; then
    ok "docker compose disponible ($(docker compose version --short))"
  else
    ko "'docker compose' introuvable — installe Docker Compose v2"
  fi
else
  ko "docker n'est pas installe"
fi

# ---------------------------------------------------------------- 2. Python
step "2. Python"
if command -v python3 >/dev/null 2>&1; then
  ok "python3 present ($(python3 --version 2>&1))"
else
  ko "python3 introuvable — necessaire pour lancer pytest en local"
fi

# ---------------------------------------------------------------- 3. Fork
step "3. Ton fork"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  origin=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -z "${origin}" ]; then
    ko "aucun remote 'origin' — clone ton fork, pas l'upstream"
  elif echo "${origin}" | grep -qi "${UPSTREAM_PATTERN}"; then
    ko "origin pointe sur l'upstream (${origin}) — forke le depot et clone TON fork"
  else
    ok "origin pointe sur ton fork (${origin})"
  fi
else
  ko "tu n'es pas dans un depot git"
  origin=""
fi

# ------------------------------------------------- 4. GitHub Actions activees
step "4. GitHub Actions sur ton fork"
actions_url=""
if [ -n "${origin}" ]; then
  slug=$(echo "${origin}" | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')
  actions_url="https://github.com/${slug}/actions"
  echo "  GitHub desactive les workflows sur un fork tant que tu n'as pas clique"
  echo "  le bandeau de confirmation. Sans ce clic, l'etage 2 du workshop est perdu."
  echo ""
  echo "  Ouvre CETTE page : ${actions_url}"
  echo "  Clique sur « I understand my workflows, go ahead and enable them »."
  echo ""
  if [ -r /dev/tty ]; then
    printf "  Les workflows sont-ils actives sur cette page ? [o/N] "
    read -r answer </dev/tty || answer="n"
  else
    answer="n"
    echo "  (pas de terminal interactif : relance le preflight a la main pour confirmer)"
  fi
  case "${answer}" in
    o|O|y|Y) ok "Actions confirmees actives sur ${actions_url}" ;;
    *)       ko "Actions non confirmees — retourne sur ${actions_url}" ;;
  esac
else
  ko "impossible de construire l'URL des Actions sans remote origin"
fi

# ---------------------------------------------------------------- 5. Images
step "5. Images Docker"
for image in "${IMAGES[@]}"; do
  if docker image inspect "${image}" >/dev/null 2>&1; then
    ok "${image} deja presente"
  else
    echo "  ... telechargement de ${image}"
    if docker pull -q "${image}" >/dev/null 2>&1; then
      ok "${image} telechargee"
    else
      ko "echec du telechargement de ${image}"
    fi
  fi
done

# ---------------------------------------------------------------- 6. Wheels
step "6. Dependances Python hors-ligne"
mkdir -p wheels
if docker run --rm -v "$(pwd)":/w -w /w python:3.12-slim \
     pip download --no-cache-dir -q -d wheels -r app/requirements.txt >/dev/null 2>&1; then
  count=$(ls -1 wheels 2>/dev/null | wc -l | tr -d ' ')
  ok "${count} wheels dans wheels/ — le build sera hors-ligne"
else
  ko "echec du telechargement des wheels (reseau ?)"
fi

if [ -x .venv/bin/python ]; then
  ok "environnement Python local deja present (.venv)"
else
  if python3 -m venv .venv >/dev/null 2>&1 \
     && .venv/bin/pip install -q --upgrade pip >/dev/null 2>&1 \
     && .venv/bin/pip install -q -r requirements-dev.txt >/dev/null 2>&1; then
    ok "environnement Python local cree (.venv) — 'make test' fonctionnera hors-ligne"
  else
    ko "impossible de creer .venv — 'make test' ne pourra pas tourner"
  fi
fi

# ---------------------------------------------------------- 7. Stack de bout en bout
step "7. Demarrage de la stack"
test -f .env || cp .env.example .env

for entry in "APP_PORT:8000" "POSTGRES_HOST_PORT:5433" "PROMETHEUS_PORT:9090" "GRAFANA_PORT:3000"; do
  var="${entry%%:*}"; default="${entry##*:}"
  value=$(grep -E "^${var}=" .env | cut -d= -f2); value=${value:-${default}}
  if lsof -nP -iTCP:"${value}" -sTCP:LISTEN >/dev/null 2>&1; then
    ko "le port ${value} (${var}) est deja pris — change ${var} dans ton .env"
  else
    ok "port ${value} (${var}) libre"
  fi
done

if docker compose up -d --build >/dev/null 2>&1; then
  ok "docker compose up reussi"
  port=$(grep -E '^APP_PORT=' .env | cut -d= -f2); port=${port:-8000}
  health="ko"
  for _ in $(seq 1 30); do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${port}/health" || true)" = "200" ]; then
      health="ok"; break
    fi
    sleep 2
  done
  if [ "${health}" = "ok" ]; then
    ok "GET /health repond 200 sur le port ${port}"
  else
    ko "GET /health n'a jamais repondu 200 (port ${port} deja pris ?)"
  fi
else
  ko "docker compose up a echoue"
fi

# ---------------------------------------------------------------- 8. Nettoyage
step "8. Nettoyage"
if docker compose down -v --remove-orphans >/dev/null 2>&1; then
  ok "stack arretee et volumes supprimes"
else
  ko "le nettoyage a echoue — lance 'docker compose down -v' a la main"
fi

# ---------------------------------------------------------------- Resume
echo ""
echo "=============================================="
echo " Resume — a copier-coller dans le canal"
echo "=============================================="
echo "\`\`\`"
echo "Preflight — From Code to Observable"
echo "Machine : $(uname -s) $(uname -m)"
for line in "${RESULTS[@]}"; do echo "${line}"; done
if [ "${FAILURES}" -eq 0 ]; then
  echo ""
  echo "Tout est vert. On se voit en salle."
else
  echo ""
  echo "${FAILURES} point(s) a regler avant la seance."
fi
echo "\`\`\`"

exit $(( FAILURES > 0 ? 1 : 0 ))
