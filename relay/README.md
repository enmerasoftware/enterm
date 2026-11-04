# Enterm Relay

Mac ile telefon arasında şifreli baytları taşır, bildirimi APNs'e iletir. İçeriği okuyamaz, kayıt tutmaz, bağımlılığı yoktur.

Yerelde çalıştırmak:

    node relay/server.mjs

Test:

    node --test relay/

Ayarlar ortam değişkeniyledir:

| Değişken | Anlamı |
|---|---|
| `PORT`, `HOST` | Dinlenen adres (varsayılan `127.0.0.1:8787`) |
| `RELAY_TLS_CERT`, `RELAY_TLS_KEY` | TLS. Yoksa önünde TLS sonlandıran bir sunucu olmalıdır |
| `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` | APNs sağlayıcı anahtarı. Anahtar sunucuda kalır, depoya girmez |
| `APNS_HOST` | Geliştirme için `https://api.sandbox.push.apple.com` |

Canlıda değildir. Yayına almak ve APNs anahtarını koymak Sinan Bey'in kararıdır.
