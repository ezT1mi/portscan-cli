#!/bin/bash

GITHUB_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/portscan-cli.sh"
INSTALL_PATH="/usr/local/bin/portscan"

# Benötigte Pakete (netcat-openbsd statt nc für Ubuntu/Debian)
REQUIRED_DEPS=(flock xxd jq)
NETCAT_PKG=""

# Erkennen, welcher netcat-Paketname verwendet wird
detect_netcat_pkg() {
  if command -v apt >/dev/null 2>&1; then
    NETCAT_PKG="netcat-openbsd"
  elif command -v pacman >/dev/null 2>&1; then
    NETCAT_PKG="gnu-netcat"
  elif command -v dnf >/dev/null 2>&1; then
    NETCAT_PKG="nmap-ncat"
  else
    NETCAT_PKG="netcat" # fallback
  fi
}

install_dependencies() {
  echo "🔍 Prüfe und installiere Abhängigkeiten..."

  detect_netcat_pkg
  REQUIRED_DEPS+=("$NETCAT_PKG")

  MISSING=()

  for pkg in "${REQUIRED_DEPS[@]}"; do
    if ! command -v "${pkg%%-*}" >/dev/null 2>&1; then
      MISSING+=("$pkg")
    fi
  done

  if [ ${#MISSING[@]} -eq 0 ]; then
    echo "✅ Alle Abhängigkeiten sind installiert."
    return
  fi

  echo "Benötigte Pakete werden installiert: ${MISSING[*]}"

  if command -v apt >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y "${MISSING[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm "${MISSING[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "${MISSING[@]}"
  else
    echo "❌ Kein unterstützter Paketmanager gefunden. Bitte installiere manuell: ${MISSING[*]}"
    exit 1
  fi
}

install_script() {
  echo "⬇️ Lade portscan-cli.sh von GitHub..."
  tmpfile=$(mktemp)
  curl -sL "$GITHUB_URL" -o "$tmpfile" || {
    echo "❌ Fehler beim Herunterladen."
    rm -f "$tmpfile"
    exit 1
  }

  chmod +x "$tmpfile"

  echo "⬆️ Installiere portscan nach $INSTALL_PATH (sudo benötigt)..."
  sudo mv "$tmpfile" "$INSTALL_PATH" || {
    echo "❌ Fehler beim Verschieben der Datei."
    rm -f "$tmpfile"
    exit 1
  }

  echo "✅ Installation abgeschlossen."
  echo "Du kannst nun 'portscan' im Terminal verwenden."
  echo "Mit 'portscan -h' bekommst du eine Übersicht der Befehle."
}

main() {
  install_dependencies
  install_script
}

main
