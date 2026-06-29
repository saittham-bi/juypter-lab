import os
from pathlib import Path

from dotenv import load_dotenv

c = get_config()  # noqa: F821

PROJECT_ROOT = Path(__file__).resolve().parent
DOTENV_PATH = PROJECT_ROOT / ".env"

if DOTENV_PATH.exists():
    load_dotenv(DOTENV_PATH, override=False)


def _get_env(*names, default=""):
    for name in names:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return default


mistral_api_key = _get_env("MISTRAL_API_KEY", "JELASTIC_MISTRAL_API_KEY", "MISTRALAI_API_KEY")
if mistral_api_key:
    os.environ["MISTRAL_API_KEY"] = mistral_api_key

# ── Server ────────────────────────────────────────────────────────────────────
# Auf 127.0.0.1 lauschen – Apache leitet von aussen weiter
c.ServerApp.ip            = "127.0.0.1"
c.ServerApp.port          = int(os.environ.get("JUPYTER_PORT", 8888))
c.ServerApp.open_browser  = False
c.ServerApp.root_dir      = os.path.join(os.path.dirname(__file__), "notebooks")

# ── Sicherheit ────────────────────────────────────────────────────────────────
# Token aus Umgebungsvariable – PFLICHT für Produktivbetrieb
token = os.environ.get("JUPYTER_TOKEN", "")
if not token:
    raise RuntimeError(
        "JUPYTER_TOKEN ist nicht gesetzt! "
        "Bitte in den Virtuozzo Umgebungsvariablen definieren."
    )
c.ServerApp.token    = token
c.ServerApp.password = ""

# Zugriff von aussen über Apache-Proxy erlauben
c.ServerApp.allow_origin        = "*"
c.ServerApp.allow_remote_access = True

# Base URL – muss mit Apache ProxyPass übereinstimmen
c.ServerApp.base_url = os.environ.get("JUPYTER_BASE_URL", "/")

# ── Jupyter AI ────────────────────────────────────────────────────────────────
# Mistral AI via environment variable (works for local .env and Jelastic vars)
if mistral_api_key:
    os.environ["MISTRAL_API_KEY"] = mistral_api_key
    os.environ.setdefault("MISTRAL_MODEL", "mistral-small-latest")

# Infomaniak Mistral via OpenAI-kompatiblem Endpunkt
product_id = _get_env("INFOMANIAK_PRODUCT_ID")
if product_id:
    infomaniak_api_key = _get_env("INFOMANIAK_API_KEY", "OPENAI_API_KEY")
    if infomaniak_api_key:
        os.environ["OPENAI_API_KEY"] = infomaniak_api_key
    c.AiExtension.openai_api_key = infomaniak_api_key
    c.AiExtension.openai_api_base_url = (
        f"https://api.infomaniak.com/2/ai/{product_id}/openai/v1"
    )

# ── Logging ───────────────────────────────────────────────────────────────────
c.Application.log_level = "INFO"
