# Enterm

Terminal görünümlü çalışma ortamı. Resmi programları (Claude Code, Codex, Antigravity, Gemini, opencode, Grok, GitHub Copilot, Cursor ya da kendi eklediğiniz bir program) değiştirmeden çalıştırır. Şu an macOS sürümü.

Üç temel kural: hafif çalışır, ayar dosyalarınıza dokunmaz, kullanmadığınız özellik yük bindirmez.

## Derleme

```bash
scripts/bundle.sh release
open build/Enterm.app
```

Xcode kurulu olmalı (`/Applications/Xcode.app`). Testler:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Yapı

- `Sources/EntermCore`: Arayüzden bağımsız çekirdek. AppKit, UIKit, SwiftUI almaz; iOS istemcisi buradan başlar.
- `Sources/entermd`: Oturum servisi. Pseudo terminallerin sahibidir, uygulama kapanınca oturumlar sürer, iş kalmayınca kapanır.
- `Sources/enterm`: Kabuk entegrasyonu ve kancaların çağırdığı küçük komut, ayrıca ajanlar arası yerel MCP köprüsü.
- `Sources/EntermApp`: macOS arayüzü. Tuval ve terminaller AppKit, sayfa ve diyaloglar SwiftUI.
- `Sources/CPTY`: `forkpty` sarmalayıcısı.

Kurallar: `.zshrc`, `~/.claude`, `~/.codex` değişmez. Entegrasyon başlatma argümanı ve ortam değişkeniyle gelir. Abonelik token'ı Enterm'e gelmez, ayrı hesap `CLAUDE_CONFIG_DIR` ve `CODEX_HOME` ile resmi programda durur.

## Yapı Taşları

- **Karşılama ve tur:** `Sources/EntermApp/FirstImpression.swift`. İlk açılışta bir kez, komut paletinden yeniden.
- **Ana ekran:** Hiçbir şey açık değilken pencere tek komut satırıdır. Yazıp Enter'a basılır: boşsa varsayılan program, klasörse orada, başka bir şeyse komut olarak çalışır.
- **Projeler:** Üst sekmeler. Her oturum açıldığı projeye bağlıdır, başka projedeki oturum çalışmaya devam eder.
- **Tuval:** Oturumlar ve görünümler (Not, Web Sayfası, Tarayıcı, Beyaz Tahta, Dosyalar, Video, iOS Simülatörü). Taşıma, boyutlandırma, gruplar, kayıtlı yerleşimler, geri alma, yarım ekran yerleşimi: `CanvasView.swift`, `Workspace.swift`.
- **Sohbet görünümü:** `⌘⇧M`. Programın kendi döküm dosyasını okur, terminale yazar: `ChatView.swift`, `Sources/EntermCore/Chat.swift`.
- **Çentik:** `Notch.swift`. Yalnız program çalışırken vardır.
- **Yerel dikte:** `Whisper.swift`. `whisper-cli` yalnız dikte sırasında çalışır, model isteyince iner.
- **Hareket kuralı:** Hareket yalnız bir şey olduğunda çalışır, boşta sıfır. Pencere görünmüyorsa, Düşük Güçlü modda ya da "hareketi azalt" açıksa kapanır (`MotionPolicy`).

## İzinler Ve Tarayıcı

- Varsayılan şablon **Serbest**: program düz terminaldeki gibi kendi kurallarıyla çalışır, sorusu hemen ekrana gelir. Kutu "Onay İstiyor" diye yanar. Daha sıkı şablonlar (Salt Okuma, Geliştirme, Yönetici, Sunucu Bakımı) Enterm'in kartıyla karar verir.
- **Tek Tık Onay** (Ayarlar → Güvenlik, kapalı) soruyu kutunun altında da gösterir, programın kendi sorusu en çok 45 saniye bekler.
- **Safari** (Ayarlar → Tarayıcı, kapalı): ajanlar kendi penceresinde Safari'yi kullanır, site başına izin sorulur, izinli siteden çıkan sayfa okunmaz. macOS'un sorusu yalnız bu ayar açıkken ve "Dene" ile gelir.
- **Girişleri Hatırla** (kapalı): Enterm'in kendi tarayıcısı hesapları kapanınca da tutar.

## Test Sürücüsü

`ENTERM_DEBUG_DIR` verilirse uygulama `SIGUSR1` ile `<dir>/cmd` dosyasındaki komutları çalıştırır (`do <komut>`, `type <metin>`, `shot <dosya>`). Bkz. `scripts/run-test.sh`, `scripts/drive.sh`, `scripts/test-bridge.sh`. Testler sahte `claude` ve geçici `HOME` ile çalışır. `ENTERM_START_TERMINAL=1` turu atlayıp terminalle başlatır. Sürücüye sinyal göndermeden önce uygulamanın açılmasını bekleyin: hazır olmadan gelen `SIGUSR1` süreci kapatır.

## Telefon

- `ios/`: iOS uygulaması. `scripts/build-ios.sh <simülatör kimliği>` ile derlenir, `ios/project.yml` xcodegen ile projeye dönüşür.
- `relay/`: aktarım ve bildirim servisi, bağımlılığı yok. Canlıda değil, ayrıntı `relay/README.md`.
- Eşleşme: QR kodunda geçici açık anahtar var, iki taraf X25519 ile ortak sır üretir, kişi altı haneli sayıyı karşılaştırır. Aktarım yalnız şifreli bayt görür, her bağlantı yeni anahtar kullanır.
- Eşleşen cihazlar `devices.json` içinde, 0600 izinle. Telefonda anahtar Anahtar Zinciri'nde.
- Mac penceresindeki işler (hesaplar, Git, bağlantılar, tarayıcı, ekip, yeni oturum) telefondan `appCall` ile çağrılır: `Sources/EntermApp/PhoneBridge.swift`. Pencere kapalıysa servis onu arkada açar, öne getirmez.

## İmzalı Sürümden Önce

- **Anahtar taşıma:** Eşleşen cihaz anahtarları şu an `devices.json` içinde 0600 izinle duruyor. Bu yalnız imzasız sürüm için kabul edildi (Ufuk, 2026-11-04), çünkü imzasız servis Anahtar Zinciri'ne her erişimde parola penceresi açar. İmzalı sürümde `PhoneCenter` anahtarları Anahtar Zinciri'ne taşır, `devices.json` içinde yalnız ad, tarih ve bildirim jetonu kalır, ilk açılışta eski dosyadaki anahtarlar taşınıp silinir.

