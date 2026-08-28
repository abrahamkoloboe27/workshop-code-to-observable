"""Application settings — environment variables only (12-Factor)."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # No default on purpose: the app must never guess where its database lives.
    database_url: str
    pool_min_size: int = 1
    pool_max_size: int = 5
    # Fail fast when the database is not reachable yet, instead of hanging.
    pool_timeout: float = 2.0


def get_settings() -> Settings:
    return Settings()
