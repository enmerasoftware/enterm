#!/bin/bash
# Installs or updates Enterm's website and Library server, as root, from the folder this script is in.
# Usage on the server: bash install.sh
# Writes /opt/enterm-web, the enterm-web systemd unit (its data in /var/lib/enterm-web) and the nginx directives of
# enterm.enmeraapps.com in Plesk: WebSocket upgrades keep going to the relay (8787), everything else comes here (8788).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
domain=enterm.enmeraapps.com
node=/opt/plesk/node/24/bin/node
[[ -x "$node" ]] || node=$(command -v node || true)
[[ -x "$node" ]] || { echo "node bulunamadı. Plesk → Araçlar → Node.js ile 24 sürümünü kurun." >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "root olarak çalıştırın." >&2; exit 1; }

mkdir -p /opt/enterm-web.new
cp -R "$here/public" /opt/enterm-web.new/public
install -m 0644 "$here/server.mjs" "$here/rules.mjs" "$here/TAGS.md" "$here/admin.html" /opt/enterm-web.new/
chmod -R a+rX /opt/enterm-web.new
rm -rf /opt/enterm-web.old
[[ -d /opt/enterm-web ]] && mv /opt/enterm-web /opt/enterm-web.old
mv /opt/enterm-web.new /opt/enterm-web

cat > /etc/systemd/system/enterm-web.service <<UNIT
[Unit]
Description=Enterm website and Library
After=network.target

[Service]
Environment=PORT=8788
Environment=HOST=127.0.0.1
ExecStart=$node /opt/enterm-web/server.mjs
StateDirectory=enterm-web
StateDirectoryMode=0700
Restart=always
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable enterm-web >/dev/null 2>&1
systemctl restart enterm-web
sleep 1
systemctl is-active enterm-web
curl -fsS http://127.0.0.1:8788/health >/dev/null && echo "Site ve Kütüphane 127.0.0.1:8788 üzerinde."

conf=/var/www/vhosts/system/$domain/conf/vhost_nginx.conf
if [[ -d $(dirname "$conf") ]] && ! grep -q enterm_port "$conf" 2>/dev/null; then
  cp "$conf" "$conf.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  cat > "$conf" <<'NGINX'
# Enterm: WebSocket upgrades go to the relay, everything else to the website and Library server.
location ~ ^/ {
    set $enterm_port 8788;
    set $enterm_conn "";
    if ($http_upgrade ~* "^websocket$") {
        set $enterm_port 8787;
        set $enterm_conn "upgrade";
    }
    proxy_pass http://127.0.0.1:$enterm_port;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $enterm_conn;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header CF-Connecting-IP $http_cf_connecting_ip;
    proxy_read_timeout 3600s;
    client_max_body_size 128k;
}
NGINX
  if command -v plesk >/dev/null; then plesk sbin httpdmng --reconfigure-domain "$domain" >/dev/null; fi
  if nginx -t 2>/dev/null; then
    systemctl reload nginx
    echo "nginx: $domain yeni yönergelerle yüklendi."
  else
    echo "nginx yapılandırması geçmedi; eski hali geri alınıyor." >&2
    latest=$(ls -t "$conf".bak-* 2>/dev/null | head -1)
    [[ -n "$latest" ]] && cp "$latest" "$conf"
    command -v plesk >/dev/null && plesk sbin httpdmng --reconfigure-domain "$domain" >/dev/null
    exit 1
  fi
fi
echo "Yönetim sayfası: https://$domain/admin"
echo "Yönetici anahtarı: /var/lib/enterm-web/admin-token (yalnız root okur)"
