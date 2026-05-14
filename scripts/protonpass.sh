#!/usr/bin/env bash
# =============================================================================
# scripts/protonpass.sh – Proton Pass CLI Hilfsfunktionen
# =============================================================================

PASS_CLI_BIN="pass-cli"
PASS_CLI_INSTALL_URL="https://proton.me/download/pass-cli/install.sh"
# Schlüsselprovider auf Dateisystem setzen (wichtig für Server-Umgebungen)
export PROTON_PASS_KEY_PROVIDER=fs

pass_install() {
  # Prüfen, ob bereits installiert und im PATH
  if command -v "$PASS_CLI_BIN" &>/dev/null; then
    echo "Proton Pass CLI bereits installiert: $$(command -v "$$PASS_CLI_BIN")"
    return 0
  fi

  echo "Installiere Proton Pass CLI ..."
  
  # Installation ausführen
  if ! curl -fsSL "$PASS_CLI_INSTALL_URL" | bash; then
    echo "Fehler bei der Installation."
    return 1
  fi

  # Kurze Verzögerung, um sicherzustellen, dass die Datei geschrieben wurde
  sleep 1

  # Erneut prüfen, ob im PATH verfügbar
  if command -v "$PASS_CLI_BIN" &>/dev/null; then
    echo "Proton Pass CLI erfolgreich installiert."
    return 0
  fi

  # Fallback: Prüfen im Standard-Verzeichnis ~/.local/bin, falls PATH nicht aktualisiert wurde
  if [ -x "$$HOME/.local/bin/$$PASS_CLI_BIN" ]; then
    echo "Hinweis: CLI installiert, aber nicht im systemweiten PATH."
    echo "Füge '$HOME/.local/bin' temporär zum PATH hinzu."
    export PATH="$$HOME/.local/bin:$$PATH"
    echo "Proton Pass CLI für diese Session verfügbar gemacht."
    return 0
  else
    echo "Fehler: pass-cli wurde weder im PATH noch in ~/.local/bin gefunden."
    echo "Bitte prüfen Sie die Installationsausgabe oder fügen Sie das Installationsverzeichnis manuell zum PATH hinzu."
    return 1
  fi
}

pass_login() {
  command -v "$PASS_CLI_BIN" &>/dev/null || { echo "pass-cli nicht gefunden. Bitte zuerst 'install' ausführen."; return 1; }
  # Die Variable PROTON_PASS_KEY_PROVIDER ist bereits global gesetzt
  "$PASS_CLI_BIN" login
}

pass_logout() {
  command -v "$PASS_CLI_BIN" &>/dev/null || return 0
  "$PASS_CLI_BIN" logout 2>/dev/null \
    && echo "Proton Pass Logout erfolgreich" \
    || echo "Proton Pass: keine aktive Session"
}

pass_status() {
  command -v