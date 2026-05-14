#!/usr/bin/env bash
# =============================================================================
# startup.sh
# Startup-Script für Virtuozzo PaaS – startet JupyterLab automatisch
# =============================================================================
set -euo pipefail

WORKDIR="/var/www/webroot/ROOT"
VENV_DIR="$WORKDIR/.venv"
LOG="$WORKDIR/startup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "================================================================"
log " Startup: JupyterLab auf Virtuozzo PaaS"
log "================================================================"

cd "$WORKDIR"

# =============================================================================
# 1. Virtualenv aktivieren
# =============================================================================
if [ -d "$VENV_DIR" ]; then
  source "$VENV_DIR/bin/activate"
  log "Virtualenv aktiviert ($(pip --version))"
else
  log "FEHLER: Virtualenv nicht gefunden – deploy.sh zuerst ausführen"
  exit 1
fi

# =============================================================================
# 2. Proton Pass (falls verfügbar)
# =============================================================================
if [ -f "$WORKDIR/scripts/protonpass.sh" ]; then
  source "$WORKDIR/scripts/protonpass.sh"
  if [ -t 0 ]; then
    pass_login && log "Proton Pass eingeloggt" || log "Proton Pass Login fehlgeschlagen"
  else
    log "Nicht-interaktiv: Proton Pass Login übersprungen"
  fi
else
  log "Proton Pass Script nicht gefunden – übersprungen"
fi

# =============================================================================
# 3. JupyterLab starten
# =============================================================================
log "--- JupyterLab starten ---"

# Laufende Instanz beenden
pkill -f "jupyter lab" 2>/dev/null || true
sleep 1

# Stopp-Hook mit Proton Pass Logout
cat > "$WORKDIR/scripts/stop_jupyter.sh" << STOPSCRIPT
#!/usr/bin/env bash
# Stopp-Script für JupyterLab
source "${WORKDIR}/scripts/protonpass.sh" 2>/dev/null || true
pkill -f "jupyter lab" 2>/dev/null || true
pass_logout 2>/dev/null || true
echo "[stop] JupyterLab gestoppt"
STOPSCRIPT
chmod +x "$WORKDIR/scripts/stop_jupyter.sh"

# JupyterLab als Hintergrundprozess starten
source "$VENV_DIR/bin/activate"
exec jupyter lab \\
  --config="${WORKDIR}/jupyter_lab_config.py" \\
  >> "$WORKDIR/jupyter.log" 2>&1 &
JUPYTER_PID=$!
log "JupyterLab gestartet (PID $JUPYTER_PID)"
echo "$JUPYTER_PID" > "$WORKDIR/jupyter.pid"

# =============================================================================
# 4. Abschlusskontrolle
# =============================================================================
log "Warte auf JupyterLab ..."
for i in 1 2 3 4 5; do
  sleep 3
  if curl -sf "http://127.0.0.1:${JUPYTER_PORT:-8888}/api" >/dev/null 2>&1; then
    log "JupyterLab antwortet (Versuch $i)"
    break
  fi
  log "Warte ... ($i/5)"
done

if curl -sf "http://127.0.0.1:${JUPYTER_PORT:-8888}/api" >/dev/null 2>&1; then
  log "================================================================"
  log " ERFOLGREICH GESTARTET"
  log " JupyterLab läuft intern auf Port ${JUPYTER_PORT:-8888}"
  log "================================================================"
else
  log "WARNUNG: JupyterLab antwortet noch nicht"
  log "  Log prüfen: tail -f $WORKDIR/jupyter.log"
fi</content>
<parameter name="filePath">startup.sh