#!/bin/bash

# Version des lokalen Scripts
VERSION="1.0"
GITHUB_VERSION_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/version.txt"
GITHUB_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/portscan-cli.sh"
INSTALL_PATH="/usr/local/bin/portscan"

check_for_update() {
  latest_version=$(curl -s "$GITHUB_VERSION_URL")
  if [[ -n "$latest_version" && "$latest_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    if [[ "$latest_version" != "$VERSION" ]]; then
      echo -e "\n🔔 Eine neue Version ($latest_version) von portscan ist verfügbar! (Du nutzt $VERSION)"
      echo "Bitte führe 'portscan update' aus, um zu aktualisieren.\n"
    fi
  fi
}

show_help() {
  cat << EOF
portscan - Ein einfacher Portscanner mit Dienst- und Minecraft-Erkennung

Verwendung:
  portscan [scan]         Starte Portscan (Standardbefehl)
  portscan update         Aktualisiert das Tool von GitHub
  portscan uninstall      Entfernt das Tool vom System
  portscan -h, help       Zeigt diese Hilfe an

EOF
  exit 0
}

update_tool() {
  echo "🔄 Lösche alte Version..."
  sudo rm -f "$INSTALL_PATH"

  echo "⬇️ Lade neueste Version von GitHub..."
  tmpfile=$(mktemp)
  curl -sL "$GITHUB_URL" -o "$tmpfile" || {
    echo "❌ Fehler beim Herunterladen."
    rm -f "$tmpfile"
    exit 1
  }

  chmod +x "$tmpfile"

  echo "⬆️ Installiere neue Version nach $INSTALL_PATH (sudo benötigt)..."
  sudo mv "$tmpfile" "$INSTALL_PATH" || {
    echo "❌ Fehler beim Verschieben der Datei."
    rm -f "$tmpfile"
    exit 1
  }

  echo "✅ Update abgeschlossen."
  exit 0
}

uninstall_tool() {
  echo "⚠️ Möchtest du 'portscan' wirklich entfernen? (j/N)"
  read -r confirm
  if [[ "$confirm" =~ ^[JjYy]$ ]]; then
    sudo rm -f "$INSTALL_PATH"
    echo "🗑️ 'portscan' wurde entfernt."
  else
    echo "❎ Abgebrochen."
  fi
  exit 0
}

check_port() {
  local port=$1
  if nc -z -w1 "$IP" "$port" 2>/dev/null; then
    (
      flock 200
      echo "$port" >> "$OPEN_PORTS_FILE"
    ) 200>"$OPEN_PORTS_FILE.lock"
  fi
}

check_minecraft() {
  local port=$1

  # Handshake-Paket bauen (Minecraft Server List Ping)
  local ip_len=${#IP}
  local ip_hex=$(echo -n "$IP" | xxd -p -c 999)
  local port_hex=$(printf '%04x' "$port")
  local handshake_hex="00f202$(printf '%02x' "$ip_len")$ip_hex$port_hex""01"
  local handshake_len=$((${#handshake_hex} / 2))
  local handshake_packet="$(printf '%02x' "$handshake_len")$handshake_hex"

  local status_request="0100"

  echo "$handshake_packet$status_request" | xxd -r -p > .mc_ping_packet

  local response=$(cat .mc_ping_packet | nc "$IP" "$port" -w 3 -N 2>/dev/null | xxd -p -c 9999)

  rm -f .mc_ping_packet

  if [[ -z "$response" ]]; then
    return 1
  fi

  # JSON aus Response extrahieren (zwischen { ... })
  local json_hex=$(echo "$response" | grep -o -P '7b.*7d')
  if [[ -z "$json_hex" ]]; then
    return 1
  fi

  # JSON aus hex konvertieren
  local json=$(echo "$json_hex" | xxd -r -p 2>/dev/null)

  # Versuche lesbaren Namen aus JSON zu holen ohne jq (vereinfachte Version)
  # Falls jq vorhanden ist, besser nutzen
  if command -v jq >/dev/null 2>&1; then
    name=$(echo "$json" | jq -r '.description.text // .description // "Minecraft Server"')
    players=$(echo "$json" | jq -r '.players.online // 0')
    maxplayers=$(echo "$json" | jq -r '.players.max // 0')
  else
    # Fallback: Versuche Name aus description.text zu extrahieren (einfaches grep)
    name=$(echo "$json" | grep -oP '(?<="text":")[^"]+' | head -1)
    [[ -z "$name" ]] && name="Minecraft Server"
    players=0
    maxplayers=0
  fi

  echo "$name|$players|$maxplayers"
  return 0
}

detect_service() {
  local port=$1
  local banner=$(echo -e "" | nc "$IP" "$port" -w 2 2>/dev/null | head -n 1)
  [[ -z "$banner" ]] && echo "Unbekannter Dienst" && return

  local banner_lower=$(echo "$banner" | tr '[:upper:]' '[:lower:]')
  if [[ "$banner_lower" =~ teamspeak ]]; then
    echo "Teamspeak Server"
  elif [[ "$banner_lower" =~ ssh ]]; then
    echo "SSH Server"
  elif [[ "$banner_lower" =~ ftp ]]; then
    echo "FTP Server"
  elif [[ "$banner_lower" =~ smtp ]]; then
    echo "SMTP Server"
  elif [[ "$banner_lower" =~ http ]]; then
    echo "HTTP Server"
  elif [[ "$banner_lower" =~ nginx ]]; then
    echo "NGINX Webserver"
  elif [[ "$banner_lower" =~ apache ]]; then
    echo "Apache Webserver"
  else
    echo "Unbekannter Dienst"
  fi
}

# === START ===

check_for_update

case "$1" in
  update)
    update_tool
    ;;
  uninstall)
    uninstall_tool
    ;;
  -h|help)
    show_help
    ;;
  ""|scan)
    # Scan starten
    ;;
  *)
    echo "❌ Unbekannter Befehl: $1"
    echo "Nutze 'portscan -h' für Hilfe."
    exit 1
    ;;
esac

read -p "Gib die IP-Adresse ein, die du scannen möchtest: " IP

if [[ -z "$IP" ]]; then
  echo "Keine IP-Adresse eingegeben. Abbruch."
  exit 1
fi

read -p "Gib die Port-Range ein (z.B. 20-80): " PORT_RANGE

if ! [[ "$PORT_RANGE" =~ ^[0-9]+-[0-9]+$ ]]; then
  echo "Ungültige Port-Range. Format muss z.B. 20-80 sein."
  exit 1
fi

START_PORT=$(echo "$PORT_RANGE" | cut -d'-' -f1)
END_PORT=$(echo "$PORT_RANGE" | cut -d'-' -f2)

if (( START_PORT > END_PORT )); then
  echo "Start-Port darf nicht größer als End-Port sein."
  exit 1
fi

echo "Scanne IP $IP im Bereich $START_PORT-$END_PORT ..."
MAX_JOBS=100
OPEN_PORTS_FILE="open_ports.tmp"

rm -f "$OPEN_PORTS_FILE"
touch "$OPEN_PORTS_FILE"

for ((port=START_PORT; port<=END_PORT; port++)); do
  echo -ne "Scanne Port $port...\r"
  check_port "$port" &

  while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
    sleep 0.05
  done
done

wait
echo -e "\nScan abgeschlossen."

if [ ! -s "$OPEN_PORTS_FILE" ]; then
  echo "Keine offenen Ports gefunden."
  rm -f "$OPEN_PORTS_FILE" "$OPEN_PORTS_FILE.lock"
  exit 0
fi

echo -e "\nAnalyse der offenen Ports:"
sort -n "$OPEN_PORTS_FILE" | while read -r port; do
  mc_info=$(check_minecraft "$port")
  if [[ $? -eq 0 && -n "$mc_info" ]]; then
    IFS='|' read -r name players maxplayers <<< "$mc_info"
    echo "  - Port $port: Minecraft Server - $name ($players/$maxplayers Spieler)"
  else
    service=$(detect_service "$port")
    echo "  - Port $port: $service"
  fi
done

rm -f "$OPEN_PORTS_FILE" "$OPEN_PORTS_FILE.lock"
