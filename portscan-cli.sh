#!/bin/bash

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

# Parallel scan
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

# --- Minecraft-Check Funktion ---
check_minecraft() {
  local port=$1

  local ip_str="$IP"
  local ip_len=$(printf "%s" "$ip_str" | wc -c)
  local ip_hex=$(printf "%s" "$ip_str" | xxd -p -c 999)

  local handshake_hex="00f202$(printf '%02x' $ip_len)$ip_hex$(printf '%04x' $port | sed 's/../& /' | awk '{print $1$2}')01"
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

# --- Dienstbanner erkennen ---
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

# --- Ausgabe ---
echo -e "\nAnalyse der offenen Ports:"
sort -n "$OPEN_PORTS_FILE" | while read port; do
  mc_json=$(check_minecraft "$port")
  if [[ $? -eq 0 && -n "$mc_json" ]]; then
    if command -v jq >/dev/null 2>&1; then
	name=$(echo "$mc_json" | jq -r '.description // .description.text // .description.extra[0].text // "Minecraft Server"')
      players=$(echo "$mc_json" | jq -r '.players.online // 0')
      maxplayers=$(echo "$mc_json" | jq -r '.players.max // 0')
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
