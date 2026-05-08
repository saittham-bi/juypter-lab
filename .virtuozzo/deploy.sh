#!/usr/bin/env bash
# =============================================================================
# .virtuozzo/deploy.sh
# Vollständiges Deploy-Skript für Virtuozzo Python-Node (kein Nginx nötig)
# =============================================================================
set -euo pipefail

WORKDIR="/var/www/webroot/ROOT"
VENV_DIR="$WORKDIR/.venv"
LOG="$WORKDIR/deploy.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "================================================================"
log " Deploy: JupyterLab auf Virtuozzo PaaS (Apache-Proxy, kein Nginx)"
log "================================================================"

cd "$WORKDIR"

# =============================================================================
# 1. Python
# =============================================================================
PYTHON=$(command -v python3.11 2>/dev/null \
      || command -v python3.10 2>/dev/null \
      || command -v python3)
log "Python: $($PYTHON --version)"

# =============================================================================
# 2. Virtualenv – robust, Virtuozzo hat oft kein ensurepip
# =============================================================================
if [ ! -d "$VENV_DIR" ]; then
  log "Erstelle Virtualenv ..."
  if $PYTHON -m venv "$VENV_DIR" --upgrade-deps 2>/dev/null; then
    log "Virtualenv mit --upgrade-deps erstellt"
  elif $PYTHON -m venv "$VENV_DIR" --without-pip; then
    log "Virtualenv ohne pip – bootstrappe via get-pip.py ..."
    curl -fsSL https://bootstrap.pypa.io/get-pip.py \
      | "$VENV_DIR/bin/python" - --quiet
    log "pip bootstrapped"
  else
    log "FEHLER: Virtualenv konnte nicht erstellt werden"; exit 1
  fi
else
  log "Virtualenv vorhanden"
fi

# pip sicherstellen (repariert auch korruptes venv)
if ! "$VENV_DIR/bin/python" -m pip --version >/dev/null 2>&1; then
  log "pip fehlt – bootstrappe ..."
  curl -fsSL https://bootstrap.pypa.io/get-pip.py \
    | "$VENV_DIR/bin/python" - --quiet
fi

source "$VENV_DIR/bin/activate"
log "Virtualenv aktiv ($(pip --version))"

# =============================================================================
# 3. Pakete installieren
# =============================================================================
pip install --upgrade pip wheel setuptools --quiet
pip install -r "$WORKDIR/requirements.txt" --quiet
log "Pakete installiert"

python -m ipykernel install --user \
  --name jupyterlab-paas \
  --display-name "JupyterLab PaaS"
log "Kernel registriert"

# =============================================================================
# 4. Verzeichnisse
# =============================================================================
mkdir -p "$WORKDIR/notebooks" "$WORKDIR/data" "$WORKDIR/scripts"

# =============================================================================
# 5. JUPYTER_TOKEN prüfen
# =============================================================================
if [ -z "${JUPYTER_TOKEN:-}" ]; then
  log "WARNUNG: JUPYTER_TOKEN nicht gesetzt!"
  log "  Bitte in Virtuozzo Umgebungsvariablen setzen:"
  log "  python3 -c \"import secrets; print(secrets.token_hex(32))\""
fi

# =============================================================================
# 6. Apache als Reverse-Proxy konfigurieren
# =============================================================================
log "--- Apache Konfiguration ---"

# Apache-Konfig-Verzeichnis (Virtuozzo: /etc/apache2/conf.d oder /etc/httpd/conf.d)
APACHE_CONF_DIR=""
for d in /etc/apache2/conf.d /etc/httpd/conf.d /etc/apache2/sites-enabled; do
  if [ -d "$d" ]; then
    APACHE_CONF_DIR="$d"
    break
  fi
done

if [ -n "$APACHE_CONF_DIR" ]; then
  cp "$WORKDIR/.virtuozzo/apache.conf" "$APACHE_CONF_DIR/jupyterlab.conf"
  log "Apache-Konfig nach $APACHE_CONF_DIR/jupyterlab.conf kopiert"

  # Apache-Dienst neu starten
  if command -v apachectl >/dev/null 2>&1; then
    apachectl configtest && apachectl graceful && log "Apache neu gestartet (apachectl)"
  elif service apache2 status >/dev/null 2>&1; then
    service apache2 restart && log "Apache neu gestartet (apache2)"
  elif service httpd status >/dev/null 2>&1; then
    service httpd restart && log "Apache neu gestartet (httpd)"
  else
    log "WARNUNG: Apache konnte nicht automatisch neu gestartet werden"
    log "  Manuell: service httpd restart  ODER  apachectl graceful"
  fi
else
  log "WARNUNG: Apache-Konfig-Verzeichnis nicht gefunden"
  log "  Bitte .virtuozzo/apache.conf manuell einspielen"
fi

# =============================================================================
# 7. Proton Pass CLI
# =============================================================================
log "--- Proton Pass CLI ---"
chmod +x "$WORKDIR/scripts/protonpass.sh"
source "$WORKDIR/scripts/protonpass.sh"
pass_install && log "Proton Pass bereit" || log "Proton Pass Installation fehlgeschlagen"

if [ -t 0 ]; then
  pass_login && log "Proton Pass eingeloggt" || log "Login fehlgeschlagen"
else
  log "Nicht-interaktiv: SSH in den Node und 'pass-cli login' ausführen"
fi

# =============================================================================
# 8. JupyterLab starten
# =============================================================================
log "--- JupyterLab starten ---"

# Laufende Instanz beenden
pkill -f "jupyter lab" 2>/dev/null || true
sleep 1

# Stopp-Hook mit Proton Pass Logout
cat > "$WORKDIR/scripts/run_jupyter.sh" << RUNSCRIPT
#!/usr/bin/env bash
# Lädt Proton Pass Funktionen und startet JupyterLab mit Logout-Trap
source "${WORKDIR}/scripts/protonpass.sh"

_stop() {
  echo "[stop] Proton Pass Logout ..."
  pass_logout
}
trap _stop EXIT INT TERM

source "${VENV_DIR}/bin/activate"

exec jupyter lab \\
  --config="${WORKDIR}/jupyter_lab_config.py"
RUNSCRIPT
chmod +x "$WORKDIR/scripts/run_jupyter.sh"

# Als dauerhafter Hintergrundprozess starten
nohup "$WORKDIR/scripts/run_jupyter.sh" \
  >> "$WORKDIR/jupyter.log" 2>&1 &
JUPYTER_PID=$!
log "JupyterLab gestartet (PID $JUPYTER_PID)"
echo "$JUPYTER_PID" > "$WORKDIR/jupyter.pid"

# =============================================================================
# 9. Abschlusskontrolle
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
  log " ERFOLGREICH DEPLOYED"
  log " JupyterLab läuft intern auf Port ${JUPYTER_PORT:-8888}"
  log " Erreichbar über die Virtuozzo PaaS Domain"
  log " Log: tail -f $WORKDIR/jupyter.log"
  log "================================================================"
else
  log "WARNUNG: JupyterLab antwortet noch nicht"
  log "  Log prüfen: tail -f $WORKDIR/jupyter.log"
fi
