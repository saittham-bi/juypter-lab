#!/usr/bin/env bash
# =============================================================================
# scripts/protonpass.sh – Proton Pass CLI Hilfsfunktionen
# =============================================================================

PASS_CLI_BIN="pass-cli"
PASS_CLI_INSTALL_URL="https://proton.me/download/pass-cli/install.sh"
PASS_CLI_LOCAL_BIN="$HOME/.local/bin"

# Schlüsselprovider auf Dateisystem setzen (Pflicht für Server ohne GUI/Keyring)
export PROTON_PASS_KEY_PROVIDER=fs

# PATH sicherstellen – wird bei jedem source dieses Scripts gesetzt
_pass_ensure_path() {
  if [[ ":$PATH:" != *":$PASS_CLI_LOCAL_BIN:"* ]]; then
    export PATH="$PASS_CLI_LOCAL_BIN:$PATH"
  fi
}

# PATH und Umgebungsvariablen permanent in Shell-Profilen verankern
_pass_persist_env() {
  local marker="# proton-pass-cli managed"

  for profile in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    # Datei anlegen falls nicht vorhanden
    touch "$profile"

    # Nur eintragen wenn noch nicht vorhanden
    if ! grep -q "$marker" "$profile" 2>/dev/null; then
      cat >> "$profile" << PROFILE

$marker
export PATH="$PASS_CLI_LOCAL_BIN:\$PATH"
export PROTON_PASS_KEY_PROVIDER=fs
PROFILE
      echo "✓ PATH und PROTON_PASS_KEY_PROVIDER in $profile eingetragen"
    fi
  done
}

# PATH sofort aktivieren
_pass_ensure_path

pass_install() {
  # Prüfen ob bereits installiert
  if command -v "$PASS_CLI_BIN" &>/dev/null; then
    echo "✓ Proton Pass CLI bereits installiert: $(command -v "$PASS_CLI_BIN")"
    _pass_persist_env
    return 0
  fi

  echo "→ Installiere Proton Pass CLI ..."
  if ! curl -fsSL "$PASS_CLI_INSTALL_URL" | bash; then
    echo "✗ Fehler bei der Installation"
    return 1
  fi

  sleep 1
  _pass_ensure_path

  if command -v "$PASS_CLI_BIN" &>/dev/null; then
    echo "✓ Proton Pass CLI installiert: $(command -v "$PASS_CLI_BIN")"
    _pass_persist_env
    return 0
  fi

  # Fallback: direkt im Installationspfad prüfen
  if [ -x "$PASS_CLI_LOCAL_BIN/$PASS_CLI_BIN" ]; then
    echo "✓ Proton Pass CLI installiert in $PASS_CLI_LOCAL_BIN"
    _pass_persist_env
    return 0
  fi

  echo "✗ Installation fehlgeschlagen – pass-cli nicht gefunden"
  return 1
}

pass_login() {
  _pass_ensure_path
  command -v "$PASS_CLI_BIN" &>/dev/null \
    || { echo "✗ pass-cli nicht gefunden. Bitte zuerst 'install' ausführen."; return 1; }

  echo "→ Proton Pass Login (PROTON_PASS_KEY_PROVIDER=$PROTON_PASS_KEY_PROVIDER) ..."
  "$PASS_CLI_BIN" login
}

pass_logout() {
  _pass_ensure_path
  command -v "$PASS_CLI_BIN" &>/dev/null || return 0
  "$PASS_CLI_BIN" logout 2>/dev/null \
    && echo "✓ Proton Pass Logout erfolgreich" \
    || echo "⚠ Proton Pass: keine aktive Session"
}

pass_status() {
  _pass_ensure_path
  command -v "$PASS_CLI_BIN" &>/dev/null \
    || { echo "⚠ Proton Pass CLI nicht installiert"; return 1; }
  echo "PROTON_PASS_KEY_PROVIDER=$PROTON_PASS_KEY_PROVIDER"
  "$PASS_CLI_BIN" status 2>/dev/null || echo "⚠ Keine aktive Session"
}

# Direktaufruf: ./scripts/protonpass.sh [install|login|logout|status]
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    install) pass_install ;;
    login)   pass_install && pass_login ;;
    logout)  pass_logout ;;
    status)  pass_status ;;
    *) echo "Verwendung: $0 {install|login|logout|status}"; exit 1 ;;
  esac
fi
