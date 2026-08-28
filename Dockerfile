FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /srv

# Offline install: the wheels are downloaded once by `make preflight`.
COPY wheels/ /wheels/
RUN test -n "$(ls -A /wheels 2>/dev/null)" || { \
      echo ""; \
      echo "ERREUR : le dossier wheels/ est vide."; \
      echo "Lance 'make preflight' pour telecharger les dependances,"; \
      echo "puis relance 'make build'. Le build ne va PAS chercher sur le reseau."; \
      echo ""; \
      exit 1; \
    }

COPY . .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r app/requirements.txt

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
