# Aktarım Servisini Yayına Alma

Telefonun evden uzakta da bağlanması için gerekir. Bağımlılığı yok, tek dosya: `relay/server.mjs`. Laravel gerekmez, panel de gerekmez.

Hedef adres: `wss://enterm.enmeraapps.com`.

## 1. Alan Adı

`enterm.enmeraapps.com` için sunucuya A kaydı açılır.

## 2. Servis

Sunucuda:

```bash
mkdir -p /opt/enterm-relay
# server.mjs dosyasını buraya kopyalayın
cat > /etc/systemd/system/enterm-relay.service <<'UNIT'
[Unit]
Description=Enterm Relay
After=network.target

[Service]
Environment=PORT=8787
Environment=HOST=127.0.0.1
ExecStart=/opt/plesk/node/24/bin/node /opt/enterm-relay/server.mjs
Restart=always
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now enterm-relay
```

## 3. Web Sunucusu

Alt alan adı açılır, sertifika alınır. Ek nginx yönergesi:

```nginx
location / {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}
```

## 4. Uygulama

Ayarlar → Telefon → Aktarım Adresi: `wss://enterm.enmeraapps.com`

## 5. Bildirimler (Sonra)

Apple anahtarı alınınca `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` ortam değişkenleri servise eklenir. Anahtar sunucuda kalır, depoya girmez.

## Doğrulama

```bash
node --test relay/
curl -i https://enterm.enmeraapps.com/
```

Servis içerik görmez: yalnız şifreli baytları taşır, kayıt tutmaz.
