"""Attend que Postgres accepte les connexions avant de lancer pytest.

Au premier demarrage, la base charge db/init.sql : elle n'ecoute sur le reseau
qu'une fois ce chargement termine. Sans cette attente, pytest echouerait pour
une mauvaise raison.
"""

import sys
import time

import psycopg

TIMEOUT_SECONDS = 90


def main() -> int:
    dsn = sys.argv[1]
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        try:
            psycopg.connect(dsn, connect_timeout=2).close()
            return 0
        except Exception:
            time.sleep(1)
    print(
        "La base n'a pas repondu en "
        f"{TIMEOUT_SECONDS}s.\n"
        "Verifie 'docker compose ps' et 'docker compose logs db'.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
