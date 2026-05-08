#!/usr/bin/env bash
# =============================================================================
# scripts/protonpass.sh – Proton Pass CLI Hilfsfunktionen
# =============================================================================

PASS_CLI_BIN="pass-cli"
PASS_CLI_INSTALL_URL="https://proton.me/download/pass-cli/install.sh"

pass_install() {
  if command -v "$PASS_CLI_BIN" &>/dev/null; then
    echo "Proton Pass CLI bereits installiert: $(command -v $PASS_CLI_BIN)"
    return 0
  fi
  echo "Installiere Proton Pass CLI ..."
  curl -fsSL "$PASS_CLI_INSTALL_URL" | bash
  command -v "$PASS_CLI_BIN" &>/dev/null && echo "Proton Pass CLI installiert" || return 1
}

pass_login() {
  command -v "$PASS_CLI_BIN" &>/dev/null || { echo "pass-cli nicht gefunden"; return 1; }
  "$PASS_CLI_BIN" login
}

pass_logout() {
  command -v "$PASS_CLI_BIN" &>/dev/null || return 0
  "$PASS_CLI_BIN" logout 2>/dev/null \
    && echo "Proton Pass Logout erfolgreich" \
    || echo "Proton Pass: keine aktive Session"
}

pass_status() {
  command -v "$PASS_CLI_BIN" &>/dev/null || { echo "Proton Pass CLI nicht installiert"; return 1; }
  "$PASS_CLI_BIN" status 2>/dev/null || echo "Keine aktive Session"
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
