# Aktarım Servisini Yayına Alma

Telefonun evden uzakta da bağlanması için gerekir. Bağımlılığı yok, tek dosya: `relay/server.mjs`. Laravel gerekmez, panel de gerekmez.

Hedef adres: `wss://enterm.enmeraapps.com`.

## 1. Alan Adı (Yapıldı)

Cloudflare'de `enterm.enmeraapps.com` → `171.22.185.218`, proxied. Bölgede SSL "full", WebSocket açık. Servis 30 saniyede bir ping atar; Cloudflare'in 100 saniyelik boşta kesme sınırına takılmaz.

## 2. Plesk

1. Web Siteleri ve Alan Adları → Alan Adı Ekle → `enterm.enmeraapps.com` (boş site, DNS'i Plesk yönetmesin).
2. SSL/TLS Sertifikaları → Let's Encrypt → `enterm.enmeraapps.com`.
3. Apache ve nginx Ayarları → Ek nginx yönergeleri:

```nginx
location ~ ^/ {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}
```

`location /` Plesk'in kendi yönergesiyle çakışır; düzenli ifade biçimi onun önüne geçer.

## 3. Servis

`server.mjs` ile `install.sh` sunucuya kopyalanır, root olarak çalıştırılır:

```bash
scp relay/server.mjs relay/install.sh root@171.22.185.218:/root/enterm-relay/
ssh root@171.22.185.218 'bash /root/enterm-relay/install.sh'
```

Güncellemede aynı iki komut yeter. Betik yalnız `/opt/enterm-relay` ve `enterm-relay` systemd birimini yazar.

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
