SHELL := /bin/bash
COMPOSE := docker compose
PYTHON_IMAGE := python:3.12-slim

-include .env
export

APP_PORT ?= 8000
POSTGRES_HOST_PORT ?= 5433
GRAFANA_PORT ?= 3000
PROMETHEUS_PORT ?= 9090
DATABASE_URL ?= postgresql://$(or $(POSTGRES_USER),workshop):$(or $(POSTGRES_PASSWORD),workshop-demo-password)@localhost:$(POSTGRES_HOST_PORT)/$(or $(POSTGRES_DB),workshop)

.DEFAULT_GOAL := help
.PHONY: help preflight env venv wheels up down reset build test lint load catchup

help: ## Liste les cibles disponibles
	@echo "Cibles du workshop :"
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | awk -F'\t' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

env: ## Cree le fichier .env a partir de .env.example s'il manque
	@test -f .env || { cp .env.example .env; echo "-> .env cree depuis .env.example"; }

preflight: ## A lancer LA VEILLE : verifie ta machine, tire les images, telecharge les wheels
	@bash scripts/preflight.sh

venv: ## Cree l'environnement Python local utilise par `make test` et `make lint`
	@test -d .venv || { \
		echo "-> Creation de .venv et installation des dependances de test"; \
		python3 -m venv .venv && .venv/bin/pip install -q --upgrade pip && \
		.venv/bin/pip install -q -r requirements-dev.txt; }
	@echo "-> Environnement Python pret (.venv)"

wheels: ## Telecharge les dependances Python pour un build hors-ligne
	@echo "-> Telechargement des wheels dans wheels/ (depuis $(PYTHON_IMAGE), pour coller a l'image finale)"
	@mkdir -p wheels
	@docker run --rm -v "$(CURDIR)":/w -w /w $(PYTHON_IMAGE) \
		pip download --no-cache-dir -d wheels -r app/requirements.txt

up: env ## Demarre la stack complete (app, base, Prometheus, Grafana)
	@echo "-> Demarrage de la stack ; Grafana sur http://localhost:$(GRAFANA_PORT)"
	@$(COMPOSE) up -d --build

down: ## Arrete la stack en conservant les donnees de la base
	@echo "-> Arret de la stack (les volumes sont conserves : tes donnees restent)"
	@$(COMPOSE) down --remove-orphans

reset: env ## Repart de zero : supprime les volumes puis redemarre (utile a l'etage 4)
	@echo "-> ATTENTION : suppression des volumes, la base va se recharger depuis db/init.sql"
	@$(COMPOSE) down -v --remove-orphans
	@$(COMPOSE) up -d --build
	@echo "-> Stack redemarree a froid, base rechargee"

build: env ## Construit l'image applicative en affichant la duree
	@test -n "$$(ls -A wheels 2>/dev/null)" || { \
		echo "ERREUR : wheels/ est vide. Lance 'make preflight' (ou 'make wheels') d'abord."; \
		exit 1; }
	@echo "-> Build de l'image applicative"
	@start=$$(date +%s); \
	$(COMPOSE) build app; \
	echo "-> Build termine en $$(( $$(date +%s) - start )) secondes"

test: env ## Lance pytest en local (demarre la base si besoin)
	@test -x .venv/bin/python || { \
		echo "ERREUR : l'environnement Python local est absent."; \
		echo "Lance 'make venv' (ou 'make preflight') une fois, puis relance 'make test'."; \
		exit 1; }
	@echo "-> Demarrage de la base (au premier lancement elle charge db/init.sql, quelques secondes)"
	@$(COMPOSE) up -d db
	@.venv/bin/python scripts/wait_for_db.py "$(DATABASE_URL)"
	@echo "-> pytest"
	@DATABASE_URL="$(DATABASE_URL)" .venv/bin/python -m pytest

lint: ## Lance ruff sur le depot
	@test -x .venv/bin/ruff || { \
		echo "ERREUR : ruff n'est pas installe. Lance 'make venv' d'abord."; exit 1; }
	@echo "-> Lint du code avec ruff"
	@.venv/bin/ruff check .

load: ## Envoie 500 requetes sur /orders pour faire monter la courbe
	@bash scripts/load.sh

catchup: ## Realigne tes fichiers sur une etape : make catchup STEP=3
	@bash scripts/catchup.sh $(STEP)
