#!/usr/bin/env bash
# =============================================================================
# startup.sh – Fallback-Startskript für Node-Neustarts ohne Supervisor
#
# Normalfall: Supervisor übernimmt den automatischen Start (autostart=true)
# Fallback:   Dieses Script via @reboot Cron im Virtuozzo Dashboard eintragen:
#
#   Dashboard → Node → Config → cron → Datei öffnen und eintragen:
#   @reboot bash /var/www/webroot/ROOT/startup.sh >> /var/www/webroot/ROOT/startup.log 2>&1
# =============================================================================
set -euo pipefail

WORKDIR="/var/www/webroot/ROOT"
VENV_DIR="$WORKDIR/.venv"
LOG="$WORKDIR/startup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "================================================"
log " Startup: JupyterLab"
log "================================================"

# =============================================================================
# Supervisor prüfen – falls aktiv, übernimmt er den Start
# =============================================================================
if command -v supervisorctl >/dev/null 2>&1; then
  if supervisorctl status jupyterlab 2>/dev/null | grep -q "RUNNING"; then
    log "Supervisor läuft bereits – JupyterLab aktiv. Kein Eingriff nötig."
    exit 0
  fi
  if [ -f "/etc/supervisor/conf.d/jupyterlab.conf" ]; then
    log "Supervisor konfiguriert – starte JupyterLab via supervisorctl ..."
    supervisorctl reread && supervisorctl update
    supervisorctl start jupyterlab && log "JupyterLab via Supervisor gestartet" && exit 0
  fi
fi

# =============================================================================
# Fallback: direkter Start via nohup
# =============================================================================
log "Supervisor nicht verfügbar – starte direkt ..."

# Voraussetzungen prüfen
if [ ! -d "$VENV_DIR" ]; then
  log "FEHLER: Virtualenv fehlt – bitte deploy.sh ausführen"; exit 1
fi
if ! "$VENV_DIR/bin/python" -m pip --version >/dev/null 2>&1; then
  log "FEHLER: pip fehlt – bitte deploy.sh ausführen"; exit 1
fi
if [ -z "${JUPYTER_TOKEN:-}" ]; then
  log "FEHLER: JUPYTER_TOKEN nicht gesetzt!"; exit 1
fi

# Apache-Konfig wiederherstellen (geht bei Redeploy verloren)
APACHE_CONF_DIR=""
for d in /etc/apache2/conf.d /etc/httpd/conf.d /etc/apache2/sites-enabled; do
  if [ -d "$d" ]; then APACHE_CONF_DIR="$d"; break; fi
done
if [ -n "$APACHE_CONF_DIR" ] && [ ! -f "$APACHE_CONF_DIR/jupyterlab.conf" ]; then
  cp "$WORKDIR/.virtuozzo/apache.conf" "$APACHE_CONF_DIR/jupyterlab.conf"
  apachectl graceful 2>/dev/null && log "Apache-Konfig wiederhergestellt" || true
fi

# Proton Pass PATH sicherstellen
export PATH="$HOME/.local/bin:$PATH"
export PROTON_PASS_KEY_PROVIDER=fs
export MISTRAL_API_KEY="${MISTRAL_API_KEY:-${JELASTIC_MISTRAL_API_KEY:-${MISTRALAI_API_KEY:-}}}"
export MISTRAL_MODEL="${MISTRAL_MODEL:-mistral-small-latest}"

# Alte Instanz beenden
if [ -f "$WORKDIR/jupyter.pid" ]; then
  OLD_PID=$(cat "$WORKDIR/jupyter.pid")
  kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
  rm -f "$WORKDIR/jupyter.pid"
fi
pkill -f "jupyter lab" 2>/dev/null || true
sleep 1

# Starten mit Logout-Trap bei Beenden
source "$VENV_DIR/bin/activate"

cat > "$WORKDIR/scripts/run_jupyter.sh" << RUNSCRIPT
#!/usr/bin/env bash
export PATH="$HOME/.local/bin:\$PATH"
export PROTON_PASS_KEY_PROVIDER=fs
source "${WORKDIR}/scripts/protonpass.sh"

_stop() {
  echo "[stop] Proton Pass Logout ..."
  pass_logout
}
trap _stop EXIT INT TERM

export MISTRAL_API_KEY="${MISTRAL_API_KEY:-${JELASTIC_MISTRAL_API_KEY:-${MISTRALAI_API_KEY:-}}}"
export MISTRAL_MODEL="${MISTRAL_MODEL:-mistral-small-latest}"

source "${VENV_DIR}/bin/activate"
exec jupyter lab --config="${WORKDIR}/jupyter_lab_config.py"
RUNSCRIPT
chmod +x "$WORKDIR/scripts/run_jupyter.sh"

nohup "$WORKDIR/scripts/run_jupyter.sh" >> "$WORKDIR/jupyter.log" 2>&1 &
JUPYTER_PID=$!
echo "$JUPYTER_PID" > "$WORKDIR/jupyter.pid"
log "JupyterLab gestartet (PID $JUPYTER_PID)"

# Bereit-Check
for i in 1 2 3 4 5; do
  sleep 3
  if curl -sf "http://127.0.0.1:${JUPYTER_PORT:-8888}/api" >/dev/null 2>&1; then
    log "JupyterLab antwortet (nach ${i}x3s)"
    log "================================================"
    break
  fi
  log "Warte ... ($i/5)"
done
