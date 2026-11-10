#!/bin/bash
# Installs or updates the relay on the server, as root, next to this script's server.mjs.
# Usage on the server: bash install.sh
# It only writes /opt/enterm-relay and its own systemd unit; the web server is set up in Plesk (see DEPLOY.md).
set -e
here=$(cd "$(dirname "$0")" && pwd)
node=/opt/plesk/node/24/bin/node
[[ -x "$node" ]] || node=$(command -v node)
[[ -x "$node" ]] || { echo "node bulunamadı. Plesk → Araçlar → Node.js ile 24 sürümünü kurun." >&2; exit 1; }
mkdir -p /opt/enterm-relay
install -m 0644 "$here/server.mjs" /opt/enterm-relay/server.mjs
cat > /etc/systemd/system/enterm-relay.service <<UNIT
[Unit]
Description=Enterm Relay
After=network.target

[Service]
Environment=PORT=8787
Environment=HOST=127.0.0.1
ExecStart=$node /opt/enterm-relay/server.mjs
Restart=always
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable enterm-relay >/dev/null 2>&1
systemctl restart enterm-relay
sleep 1
systemctl is-active enterm-relay
ss -ltnp | grep -q ':8787 ' && echo "Aktarım 127.0.0.1:8787 üzerinde dinliyor."
