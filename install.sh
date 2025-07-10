#!/bin/bash

set -e

BIN_NAME="portscan"
INSTALL_PATH="/usr/local/bin/$BIN_NAME"
SCRIPT_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/portscan-cli.sh"

echo "Lade neueste Version von portscan-cli herunter..."

curl -sL "$SCRIPT_URL" -o /tmp/$BIN_NAME
chmod +x /tmp/$BIN_NAME

echo "Installiere nach $INSTALL_PATH..."
sudo mv /tmp/$BIN_NAME "$INSTALL_PATH"

echo "✅ Installation abgeschlossen. Du kannst das Tool jetzt mit 'portscan' verwenden."
