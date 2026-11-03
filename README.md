# Enterm

Terminal görünümlü çalışma ortamı. Resmi `claude`, `codex` ve `agy` programlarını değiştirmeden çalıştırır. Şu an macOS sürümü.

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

## Test Sürücüsü

`ENTERM_DEBUG_DIR` verilirse uygulama `SIGUSR1` ile `<dir>/cmd` dosyasındaki komutları çalıştırır (`do <komut>`, `type <metin>`, `shot <dosya>`). Bkz. `scripts/run-test.sh`, `scripts/drive.sh`, `scripts/test-bridge.sh`. Testler sahte `claude` ve geçici `HOME` ile çalışır.
