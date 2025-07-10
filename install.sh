#!/bin/bash

set -e

BIN_NAME="portscan"
TEMP_PATH="/tmp/$BIN_NAME"
INSTALL_PATH="/usr/local/bin/$BIN_NAME"
SCRIPT_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/portscan-cli.sh"

echo "🔧 Lade portscan-cli herunter..."
curl -sL "$SCRIPT_URL" -o "$TEMP_PATH"

chmod +x "$TEMP_PATH"
echo "📦 Installiere nach $INSTALL_PATH..."
sudo mv "$TEMP_PATH" "$INSTALL_PATH"

echo "✅ Installation abgeschlossen. Du kannst 'portscan' jetzt im Terminal verwenden!"
