import os

c = get_config()  # noqa: F821

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
# Infomaniak Mistral via OpenAI-kompatiblem Endpunkt
product_id = os.environ.get("INFOMANIAK_PRODUCT_ID", "")
if product_id:
    c.AiExtension.openai_api_key      = os.environ.get("INFOMANIAK_API_KEY", "")
    c.AiExtension.openai_api_base_url = (
        f"https://api.infomaniak.com/2/ai/{product_id}/openai/v1"
    )

# ── Logging ───────────────────────────────────────────────────────────────────
c.Application.log_level = "INFO"
