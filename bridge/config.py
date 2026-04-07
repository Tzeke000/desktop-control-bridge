from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _default_vision_workspace() -> Path:
    return Path.home() / ".openclaw" / "workspace" / "bridge-vision"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    bridge_host: str = "127.0.0.1"
    bridge_port: int = 47821
    bridge_token: str = ""

    log_dir: Path = Field(default=Path("logs"), validation_alias="BRIDGE_LOG_DIR")
    screenshot_dir: Path = Field(
        default=Path("screenshots"), validation_alias="BRIDGE_SCREENSHOT_DIR"
    )
    vision_workspace_dir: Path = Field(
        default_factory=_default_vision_workspace,
        validation_alias="BRIDGE_VISION_WORKSPACE",
    )
    macros_path: Path | None = Field(default=None, validation_alias="BRIDGE_MACROS_PATH")

    @property
    def base_dir(self) -> Path:
        return Path.cwd()


@lru_cache
def get_settings() -> Settings:
    return Settings()
