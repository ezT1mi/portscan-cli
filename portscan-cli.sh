#!/bin/bash
# portscan-cli.sh - einfacher Portscanner mit Dienst- und Minecraft-Erkennung
VERSION="1.1.1"
VERSION_NUM="1.1.1"

check_for_update() {
  if [ -f "$VERSION_FILE" ]; then
    local latest_version
    latest_version=$(head -n1 "$VERSION_FILE" | tr -d ' \t\n\r')
    if [[ -n "$latest_version" ]]; then
      compare_versions "$latest_version" "$VERSION_NUM"
      if [[ $? -eq 1 ]]; then
        echo "⚠️ Eine neue Version $latest_version ist verfügbar! Du nutzt $VERSION_NUM."
        echo "   Aktualisieren mit: portscan update"
        echo
      fi
    fi
  fi
}


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

compare_versions() {
  # Gibt 0 zurück wenn v1 >= v2, 1 wenn v1 < v2
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
  if [ -f "$VERSION_FILE" ]; then
    local latest_version
    latest_version=$(cat "$VERSION_FILE" 2>/dev/null)
    if [[ -n "$latest_version" ]]; then
      compare_versions "$latest_version" "$VERSION"
      if [[ $? -eq 1 ]]; then
        echo "⚠️ Eine neue Version $latest_version ist verfügbar! Du nutzt $VERSION."
        echo "   Aktualisieren mit: portscan update"
        echo
      fi
    fi
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

# Debug-Ausgabe (optional, kann entfernt werden)
# echo "DEBUG: PORT_RANGE='$PORT_RANGE'"

if ! [[ "$PORT_RANGE" =~ ^[0-9]+-[0-9]+$ ]]; then
  echo "Ungültige Port-Range. Format muss z.B. 20-80 sein."
  exit 1
fi

START_PORT=$(echo "$PORT_RANGE" | cut -d'-' -f1)
END_PORT=$(echo "$PORT_RANGE" | cut -d'-' -f2)

# Debug-Ausgabe (optional, kann entfernt werden)
# echo "DEBUG: START_PORT='$START_PORT'"
# echo "DEBUG: END_PORT='$END_PORT'"

if ! [[ "$START_PORT" =~ ^[0-9]+$ ]]; then
  echo "Fehler: Start-Port ist keine gültige Zahl: '$START_PORT'"
  exit 1
fi

if ! [[ "$END_PORT" =~ ^[0-9]+$ ]]; then
  echo "Fehler: End-Port ist keine gültige Zahl: '$END_PORT'"
  exit 1
fi

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
  local ip_str="$IP"
  local ip_len=$(printf "%s" "$ip_str" | wc -c)
  local ip_hex=$(printf "%s" "$ip_str" | xxd -p -c 999)
  local port_hex=$(printf '%04x' $port)
  local handshake_hex="00f202$(printf '%02x' $ip_len)$ip_hex$port_hex"01
  local handshake_len=$((${#handshake_hex} / 2))
  local handshake_packet="$(printf '%02x' $handshake_len)$handshake_hex"
  local status_request="0100"
  echo "$handshake_packet$status_request" | xxd -r -p > .mc_ping_packet
  local response=$(cat .mc_ping_packet | nc "$IP" "$port" -w 3 -N 2>/dev/null | xxd -p -c 9999)
  rm -f .mc_ping_packet
  if [[ -z "$response" ]]; then
    return 1
  fi
  local json_hex=$(echo "$response" | grep -o -P '7b.*7d')
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
  local json=$1
  local name=$(echo "$json" | grep -oP '"name"\s*:\s*"\K[^"]+')
  if [[ -z "$name" ]]; then
    echo "Minecraft Server"
  else
    echo "Minecraft Server: $name"
  fi
}

echo "Offene Ports:"
while read -r port; do
  echo -n "Port $port: "
  if check_minecraft "$port"; then
    mc_json=$(check_minecraft "$port")
    name=$(extract_mc_name "$mc_json")
    echo "$name"
  else
    detect_service "$port"
  fi
done < "$OPEN_PORTS_FILE"

rm -f "$OPEN_PORTS_FILE" "$OPEN_PORTS_FILE.lock"
exit 0
