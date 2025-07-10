#!/bin/bash

set -e

BIN_NAME="portscan"
TEMP_PATH="/tmp/$BIN_NAME"
INSTALL_PATH="/usr/local/bin/$BIN_NAME"
SCRIPT_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/portscan-cli.sh"

echo "🔍 Überprüfe benötigte Tools..."

# Liste der benötigten Programme
DEPS=(nc flock xxd)

# Optional: jq für JSON-Ausgabe
OPTIONAL_DEPS=(jq)

MISSING=()
for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    MISSING+=("$dep")
  fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
  echo "📦 Installiere fehlende Pakete: ${MISSING[*]}"

  if command -v apt &>/dev/null; then
    sudo apt update
    sudo apt install -y "${MISSING[@]}"
  elif command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm "${MISSING[@]}"
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y "${MISSING[@]}"
  else
    echo "❌ Kein unterstützter Paketmanager gefunden. Bitte installiere diese Pakete manuell: ${MISSING[*]}"
    exit 1
  fi
fi

echo "📥 Lade portscan-cli herunter..."
curl -sL "$SCRIPT_URL" -o "$TEMP_PATH"

chmod +x "$TEMP_PATH"
echo "📦 Installiere nach $INSTALL_PATH..."
sudo mv "$TEMP_PATH" "$INSTALL_PATH"

echo "✅ Installation abgeschlossen. Du kannst jetzt 'portscan' im Terminal verwenden!"

# Hinweis für jq
if ! command -v jq &>/dev/null; then
  echo "ℹ️ Hinweis: Für detaillierte Minecraft-Ausgabe kannst du 'jq' installieren:"
  echo "    sudo apt install jq"
fi
