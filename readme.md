# portscan-cli

Ein einfacher, schneller Portscanner mit Dienst- und Minecraft-Servererkennung.  
Funktioniert als eigenständiger Befehl `portscan` im Terminal.

---

## Features

- Paralleler Portscan in definierter Port-Range
- Erkennung von gängigen Diensten (SSH, HTTP, FTP, Teamspeak etc.)
- Spezieller Check für Minecraft-Server mit Spielerstatistik
- Befehle: `scan` (default), `update`, `uninstall`

---

## Installation

Du kannst `portscan` mit nur einem Befehl installieren (benötigt `curl` und sudo-Rechte):

```bash
curl -s https://raw.githubusercontent.com/ezT1mi/portscan-cli/main/install.sh | bash
