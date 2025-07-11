#!/bin/bash
# portscan-cli.sh - einfacher Portscanner mit Dienst- und Minecraft-Erkennung
VERSION="1.1 - pre-alpha"
VERSION_FILE="/usr/local/bin/portscan.version"  # Datei mit der aktuell installierten Versionsinfo (wird beim Update gesetzt)

GITHUB_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/portscan-cli.sh"
GITHUB_VERSION_URL="https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/version.txt"
INSTALL_PATH="/usr/local/bin/portscan"

show_help() {
  cat << EOF
portscan - Ein einfacher Portscanner mit Dienst- und Minecraft-Erkennung

Verwendung:
  portscan [scan]         Starte Portscan (Standardbefehl)
  portscan update         Aktualisiert das Tool von GitHub
  portscan uninstall      Entfernt das Tool vom System
  portscan -v, --version  Zeigt die installierte Version an
  portscan -h, help       Zeigt diese Hilfe an

EOF
  exit 0
}

update_tool() {
  echo "🔄 Entferne alte Version..."
  sudo rm -f "$INSTALL_PATH" "$VERSION_FILE"
  echo "⬇️ Lade neueste Version von GitHub..."
  tmpfile=$(mktemp)
  tmpverfile=$(mktemp)
  curl -sL "$GITHUB_URL" -o "$tmpfile" || {
    echo "Fehler beim Herunterladen des Scripts."
    rm -f "$tmpfile"
    exit 1
  }
  curl -sL "$GITHUB_VERSION_URL" -o "$tmpverfile" || {
    echo "Fehler beim Herunterladen der Versionsdatei."
    rm -f "$tmpfile" "$tmpverfile"
    exit 1
  }
  chmod +x "$tmpfile"
  sudo mv "$tmpfile" "$INSTALL_PATH"
  sudo mv "$tmpverfile" "$VERSION_FILE"
  echo "✅ Update abgeschlossen auf Version $(cat "$VERSION_FILE")."
  exit 0
}

uninstall_tool() {
  echo "⚠️ Möchtest du 'portscan' wirklich entfernen? (j/N)"
  read -r confirm
  if [[ "$confirm" =~ ^[JjYy]$ ]]; then
    sudo rm -f "$INSTALL_PATH" "$VERSION_FILE"
    echo "🗑️ 'portscan' wurde entfernt."
  else
    echo "❎ Abgebrochen."
  fi
  exit 0
}

is_json_valid() {
  echo "$1" | jq empty >/dev/null 2>&1
  return $?
}

compare_versions() {
  # Gibt 0 zurück wenn v1 >= v2, 1 wenn v1 < v2
  # Beispiel: compare_versions 1.1 1.0 --> 0 (1.1 >= 1.0)
  #          compare_versions 1.0 1.1 --> 1 (1.0 < 1.1)
  local v1=(${1//./ })
  local v2=(${2//./ })
  local len=$(( ${#v1[@]} > ${#v2[@]} ? ${#v1[@]} : ${#v2[@]} ))
  for ((i=0; i<len; i++)); do
    local n1=${v1[i]:-0}
    local n2=${v2[i]:-0}
    if (( n1 > n2 )); then
      return 0
    elif (( n1 < n2 )); then
      return 1
    fi
  done
  return 0
}

check_for_update() {
  # Lädt die Version von GitHub und vergleicht mit aktueller Script-Version
  local latest_version
  latest_version=$(curl -s "$GITHUB_VERSION_URL" || echo "")
  if [[ -z "$latest_version" ]]; then
    return
  fi
  compare_versions "$latest_version" "$VERSION"
  if [[ $? -eq 1 ]]; then
    echo "⚠️ Eine neue Version $latest_version ist verfügbar! Du nutzt $VERSION."
    echo "   Aktualisieren mit: portscan update"
    echo
  fi
}

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
  -v|--version)
    echo "portscan Version $VERSION"
    exit 0
    ;;
  ""|scan)
    ;;
  *)
    echo "❌ Unbekannter Befehl: $1"
    echo "Nutze 'portscan -h' für Hilfe."
    exit 1
    ;;
esac

# Versionscheck vor Scan starten
check_for_update

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

check_port() {
  local port=$1
  if nc -z -w1 "$IP" "$port" 2>/dev/null; then
    (
      flock 200
      echo "$port" >> "$OPEN_PORTS_FILE"
    ) 200>"$OPEN_PORTS_FILE.lock"
  fi
}

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

check_minecraft() {
  local port=$1

  # Handshake Paket bauen (Minecraft Server List Ping v1)
  local ip_len=${#IP}
  local ip_hex=$(printf "%02x" $ip_len)
  local ip_encoded=$(echo -n "$IP" | xxd -p)
  local port_hex=$(printf '%04x' "$port")
  local handshake_data="00f20f$ip_hex$ip_encoded$port_hex01"
  local handshake_len=$(printf '%02x' $(( (${#handshake_data} / 2) )))
  local handshake_packet="$handshake_len$handshake_data"
  local status_request="0100"

  # Sende Handshake + Status Request
  printf "%b" "$(echo -n "$handshake_packet$status_request" | xxd -r -p)" > .mc_ping_packet 2>/dev/null
  local response
  response=$(cat .mc_ping_packet | nc "$IP" "$port" -w 3 -N 2>/dev/null | xxd -p -c 9999)
  rm -f .mc_ping_packet

  if [[ -z "$response" ]]; then
    return 1
  fi

  # Extrahiere JSON aus Response (zwischen { und })
  local json_hex
  json_hex=$(echo "$response" | grep -o -P '7b.*7d')
  if [[ -z "$json_hex" ]]; then
    return 1
  fi

  echo "$json_hex" | xxd -r -p 2>/dev/null
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

extract_mc_name() {
  local json="$1"

  if ! echo "$json" | jq empty >/dev/null 2>&1; then
    echo "Minecraft Server"
    return
  fi

  local desc_type
  desc_type=$(echo "$json" | jq -r '.description | type' 2>/dev/null)

  if [[ "$desc_type" == "string" ]]; then
    echo "$json" | jq -r '.description'
    return
  fi

  local name
  name=$(echo "$json" | jq -r '
    if (.description.text? != null and .description.text != "") then
      .description.text
    elif (.description.extra? and (.description.extra | type == "array")) then
      [.description.extra[].text] | join("")
    else
      empty
    end
  ' 2>/dev/null)

  if [[ -z "$name" ]]; then
    name="Minecraft Server"
  fi

  echo "$name"
}

echo -e "\nAnalyse der offenen Ports:"
sort -n "$OPEN_PORTS_FILE" | while read -r port; do
  mc_json=$(check_minecraft "$port")
  if [[ $? -eq 0 && -n "$mc_json" ]]; then
    if command -v jq >/dev/null 2>&1; then
      name=$(extract_mc_name "$mc_json")
      players=$(echo "$mc_json" | jq -r '.players.online // 0' 2>/dev/null || echo "0")
      maxplayers=$(echo "$mc_json" | jq -r '.players.max // 0' 2>/dev/null || echo "0")
      echo "  - Port $port: Minecraft Server - $name ($players/$maxplayers Spieler)"
    else
      echo "  - Port $port: Minecraft Server (JSON erkannt)"
    fi
  else
    service=$(detect_service "$port")
    echo "  - Port $port: $service"
  fi
done

rm -f "$OPEN_PORTS_FILE" "$OPEN_PORTS_FILE.lock"
