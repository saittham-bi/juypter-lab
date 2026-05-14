#!/usr/bin/env bash
# =============================================================================
# startup.sh – Startet JupyterLab nach einem Node-Neustart
# Wichtig: Apache wird auf Virtuozzo automatisch gestartet – nur neu laden!
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
# Voraussetzungen prüfen
# =============================================================================
if [ ! -d "$VENV_DIR" ]; then
  log "FEHLER: Virtualenv fehlt – bitte zuerst deploy.sh ausführen:"
  log "  bash $WORKDIR/.virtuozzo/deploy.sh"
  exit 1
fi

if ! "$VENV_DIR/bin/python" -m pip --version >/dev/null 2>&1; then
  log "FEHLER: pip fehlt im Virtualenv – bitte deploy.sh erneut ausführen"
  exit 1
fi

if [ -z "${JUPYTER_TOKEN:-}" ]; then
  log "FEHLER: JUPYTER_TOKEN nicht gesetzt!"
  log "  In Virtuozzo Umgebungsvariablen definieren."
  exit 1
fi

log "Voraussetzungen OK"

# =============================================================================
# Apache Proxy-Konfiguration sicherstellen
# Auf Virtuozzo startet Apache automatisch – wir laden nur neu (graceful reload)
# KEIN restart/start – das würde den Permission-Fehler auf Port 80 auslösen!
# =============================================================================
APACHE_CONF_DIR=""
for d in /etc/apache2/conf.d /etc/httpd/conf.d /etc/apache2/sites-enabled; do
  if [ -d "$d" ]; then
    APACHE_CONF_DIR="$d"
    break
  fi
done

if [ -n "$APACHE_CONF_DIR" ]; then

  # Konfig wiederherstellen falls sie fehlt (z.B. nach Redeploy)
  if [ ! -f "$APACHE_CONF_DIR/jupyterlab.conf" ]; then
    log "Apache-Konfig fehlt – stelle wieder her ..."
    cp "$WORKDIR/.virtuozzo/apache.conf" "$APACHE_CONF_DIR/jupyterlab.conf"
    log "Apache-Konfig wiederhergestellt"
  else
    log "Apache-Konfig vorhanden"
  fi

  # Nur neu laden (reload/graceful) – Apache läuft bereits, kein Start nötig
  # graceful: bestehende Verbindungen bleiben, neue Konfig wird aktiviert
  log "Apache Konfig neu laden ..."
  if command -v apachectl >/dev/null 2>&1; then
    apachectl configtest 2>/dev/null \
      && apachectl graceful \
      && log "Apache neu geladen (apachectl graceful)" \
      || log "WARNUNG: Apache graceful reload fehlgeschlagen – Konfig prüfen"
  elif command -v httpd >/dev/null 2>&1; then
    httpd -t 2>/dev/null \
      && kill -USR1 "$(cat /var/run/httpd/httpd.pid 2>/dev/null || echo 0)" 2>/dev/null \
      && log "Apache neu geladen (USR1 signal)" \
      || log "WARNUNG: Apache reload via signal fehlgeschlagen"
  else
    log "WARNUNG: apachectl nicht gefunden – Apache-Reload übersprungen"
  fi

else
  log "WARNUNG: Apache-Konfig-Verzeichnis nicht gefunden"
fi

# =============================================================================
# Laufende JupyterLab-Instanz beenden (falls noch vorhanden)
# =============================================================================
if [ -f "$WORKDIR/jupyter.pid" ]; then
  OLD_PID=$(cat "$WORKDIR/jupyter.pid")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    log "Beende alte JupyterLab-Instanz (PID $OLD_PID) ..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 2
  fi
  rm -f "$WORKDIR/jupyter.pid"
fi
pkill -f "jupyter lab" 2>/dev/null || true
sleep 1

# =============================================================================
# JupyterLab starten
# =============================================================================
log "Starte JupyterLab ..."

source "$VENV_DIR/bin/activate"

# Proton Pass Logout-Trap einbinden falls CLI vorhanden
PROTONPASS_HOOK=""
# PATH für pass-cli sicherstellen
export PATH="$HOME/.local/bin:$PATH"
export PROTON_PASS_KEY_PROVIDER=fs

if [ -f "$WORKDIR/scripts/protonpass.sh" ]; then
  source "$WORKDIR/scripts/protonpass.sh"
fi

if command -v pass-cli >/dev/null 2>&1; then
  PROTONPASS_HOOK="source $WORKDIR/scripts/protonpass.sh; trap pass_logout EXIT INT TERM"
  log "Proton Pass Logout-Trap aktiv"
fi

cat > "$WORKDIR/scripts/run_jupyter.sh" << RUNSCRIPT
#!/usr/bin/env bash
${PROTONPASS_HOOK}

source "${VENV_DIR}/bin/activate"

exec jupyter lab \
  --config="${WORKDIR}/jupyter_lab_config.py"
RUNSCRIPT
chmod +x "$WORKDIR/scripts/run_jupyter.sh"

nohup "$WORKDIR/scripts/run_jupyter.sh" \
  >> "$WORKDIR/jupyter.log" 2>&1 &
JUPYTER_PID=$!
echo "$JUPYTER_PID" > "$WORKDIR/jupyter.pid"
log "JupyterLab gestartet (PID $JUPYTER_PID)"

# =============================================================================
# Bereit-Check
# =============================================================================
log "Warte auf JupyterLab ..."
for i in 1 2 3 4 5; do
  sleep 3
  if curl -sf "http://127.0.0.1:${JUPYTER_PORT:-8888}/api" >/dev/null 2>&1; then
    log "JupyterLab antwortet (nach ${i}x3s)"
    break
  fi
  log "Noch nicht bereit ... ($i/5)"
done

if curl -sf "http://127.0.0.1:${JUPYTER_PORT:-8888}/api" >/dev/null 2>&1; then
  log "================================================"
  log " JupyterLab läuft auf Port ${JUPYTER_PORT:-8888}"
  log " Log: tail -f $WORKDIR/jupyter.log"
  log "================================================"
else
  log "WARNUNG: JupyterLab antwortet nicht"
  log "  Log prüfen: tail -f $WORKDIR/jupyter.log"
  exit 1
fi
