#!/usr/bin/env bash
# Rattrapage : realigne tes FICHIERS sur une etape, sans deplacer ta branche.
set -euo pipefail

STEPS=(step-00 step-01 step-02 step-03 step-04 step-05)

usage() {
  echo "Usage : make catchup STEP=<numero>"
  echo ""
  echo "Etapes disponibles :"
  echo "  0  point de depart, quatre defauts en place"
  echo "  1  la route /orders existe, les tests passent"
  echo "  2  la CI dit la verite (lint bloquant, import mort supprime)"
  echo "  3  le Dockerfile met le cache dans le bon ordre, plus de root"
  echo "  4  la stack attend que la base soit prete"
  echo "  5  Prometheus scrape l'application, le dashboard se remplit"
}

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "ERREUR : il manque le numero d'etape."
  echo ""
  usage
  exit 1
fi

raw="$1"
if ! [[ "${raw}" =~ ^[0-9]+$ ]] || [ "${raw}" -gt 5 ]; then
  echo "ERREUR : '${raw}' n'est pas une etape valide."
  echo ""
  usage
  exit 1
fi

tag="step-0${raw}"
if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "ERREUR : le tag ${tag} est introuvable dans ton clone."
  echo "Recupere les tags depuis l'upstream : git fetch upstream --tags"
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)
stamp=$(date '+%Y-%m-%d %H:%M:%S')

if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "catchup ${stamp} — avant passage a ${tag}" >/dev/null
  stashed=1
else
  stashed=0
fi

git checkout "${tag}" -- .

echo ""
echo "Tu es maintenant sur l'etat des fichiers de ${tag}."
echo "Ta branche (${branch}) et tes commits n'ont pas bouge."
if [ "${stashed}" -eq 1 ]; then
  echo "Ton travail en cours a ete mis de cote : git stash list  puis  git stash pop"
else
  echo "Tu n'avais aucune modification en cours : rien n'a ete mis de cote."
fi
echo ""
echo "Les fichiers sont dans l'index. Pour repartir propre : git status"
