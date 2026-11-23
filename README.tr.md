# Enterm

**Yapay zekâ kodlama ajanları için terminal hissini koruyan, macOS'a özgü bir tuval.**

Enterm resmi kodlama programlarını (Claude Code, Codex, Gemini, Antigravity, opencode, Grok, GitHub Copilot, Cursor ya da kendi eklediğiniz bir program) geldikleri gibi, kaydırılabilen tek bir tuvalde yan yana çalıştırır. Uygulamayı kapattığınızda oturumlar çalışmaya devam eder, ayar dosyalarınıza dokunulmaz, işi iPhone'unuzdan izleyip onaylayabilirsiniz. Ücretsiz ve açık kaynaktır; hiçbir şey olmazken işlemci kullanımı %0'da kalacak şekilde yapılmıştır.

English: [README.md](README.md)

![Enterm: tuvalde yan yana ajanlar](docs/media/hero.gif)

## Neden Enterm

- **Satıcıdan bağımsız.** İşe hangi ajan uyuyorsa onu kullanın, ya da birkaçını birden. Hesap yok, abonelik yok, bağımlılık yok.
- **Resmi programlar, değiştirilmeden.** Enterm zaten kullandığınız programları sarar; onları yamalamaz, araya girmez, yeniden yazmaz.
- **Oturumlar kapanışı atlatır.** Terminallerin sahibi arka plandaki bir servistir (`entermd`), pencereyi kapatmak işi durdurmaz.
- **Sekme şeridi değil, tuval.** Her ajan ve terminal bir kutudur; döşeyin, taşıyın, boyutlandırın, gruplayın, proje sekmelerine ayırın.
- **Telefonunuz da işin içinde.** iPhone'u uçtan uca şifreli eşleştirin, izin sorularını kilit ekranından yanıtlayın.
- **Tasarımı gereği hafif.** Boştayken hiçbir şey hareket etmez, hiçbir şey yoklama yapmaz. Kullanmadığınız özellik yük bindirmez.

## Özellikler

### Yarış

![Aynı görevde yarışan iki ajan, her biri kendi worktree'sinde](docs/media/race.png)

Bir görevi birkaç ajana verin, en iyi sonucu alın. Claude Code, Codex ve Gemini arasından iki ya da üçünü seçin; her biri aynı commit'ten açılan kendi git worktree'sini ve aynı talimatı alır, böylece yarış adil olur. Yarışanlar kendi sekmelerinde yan yana açılır; her birinin canlı şeridi geçen süreyi, değişen dosyaları, eklenen ve silinen satırları ve bayrağa doğru ilerleyen bir koşucuyu gösterir. Madalyalar bitiş sırasını işaretler.

Herkes bitirince sonuçlar sayfası her yarışanın farkını gösterir ve projenin test komutunu her yarışan için ayrı çalıştırabilir (`Package.swift`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml` ve başkalarından bulunur ya da siz yazarsınız). **Kazanan Bu** o dalı ana klasörünüze birleştirir, diğer kutuları kapatır ve yarışın açtığı bütün worktree'leri ve dalları siler. Siz seçene kadar ana klasörünüz değişmez. Komut paletinden ya da eylem menüsünden **Yarış Başlat** ile başlatılır.

![Testler ve Kazanan Bu ile yarış sonucu](docs/media/race-results.png)

### Zaman Çizelgesi

![Bir yarışın zaman çizelgesi oynatımı](docs/media/timeline.png)

Bir ajanın yaptıklarının, programın kendi dökümünden okunan hareketli bir tekrarı (Claude Code ve Codex). Her ajanın bir şeridi vardır; istekler, yanıtlar, düzenlemeler, komutlar ve okumalar renkli işaretlerle görünür. Oynatma sırasında dokunulan dosyalar yanar, uzun beklemeler kısaltılır, böylece tekrar beklemeyi değil işi gösterir. Bir yarış bütün şeritlerini birlikte oynatır. **HTML Olarak Kaydet** tekrarı paylaşılabilecek tek ve kendi içinde tam bir dosya olarak dışa aktarır; dosya istekleri ve komutları içerir, göndermeden önce bakın.

### Tuval ve projeler

- Oturumlar ve görünümler kaydırılabilen bir tuvaldeki kutulardır: döşeyin, serbestçe taşıyın, boyutlandırın, gruplayın, yerleşimleri kaydedin, geri alın.
- Proje sekmeleri tuvali tek bir projeye süzer; **Tümü** bütün kutuları gösterir. Başka projedeki oturum çalışmaya devam eder.
- İzin soruları kutuyu yakar ve tek bir yerde toplanır.
- Claude Code ve Codex için beş saatlik ve haftalık kullanım sınırları durum satırında.
- Ajanlara atanmış kartlardan oluşan bir pano: bir kartı **Sürüyor**'a taşımak onu ajanına gönderir, ajan sonucu bildirir.
- Adı verilmemiş kutular programın kendi oturum başlığını gösterir; oturumun dinlediği portlar kutuda görünür.
- Sohbet görünümü (`⌘⇧M`) bir oturumu, programın kendi dökümünden okunan bir konuşma olarak gösterir.
- whisper.cpp ile yerel dikte; yalnız siz dikte ederken çalışır.
- Ayarlar'dan açtığınız hazır beceri paketleri (video, yazılım, görsel), `~/.claude`'a yazmadan oturum başına yüklenir. Bkz. [`skills/`](skills/).
- `enterm://` bağlantıları bir klasörü bir program ve görevle, bir oturumu, bir ayar sayfasını ya da panoyu açar. Program başlatacak bağlantı önce sorar.

### Ajanlar tuvali yönetir (MCP)

Yerel bir MCP köprüsü ajanların tuvali kendilerinin yönetmesini sağlar: tuvalin durumunu okumak, kutu açmak (hemen ya da sonraya sıralı), ekip kurmak, git worktree açmak, kendi açtıkları kutuları kapatmak, pano kartı eklemek ve taşımak, içerik göstermek ve düzenlemek. Bağlamı paylaşmak için iki kutu arasına çizgi çekin. Kutu açan araçlar oturumun yetki kartındaki "Başka Ajana İş Verme" iznine bağlıdır ve bir kartı Bitti'ye yalnız siz taşıyabilirsiniz.

### Telefon

iPhone uygulaması Mac'inizle bir QR koduyla eşleşir: iki taraf X25519 ile ortak bir sır üretir, siz de altı haneli bir sayıyı karşılaştırırsınız. Aradaki aktarım servisi yalnız şifreli bayt görür ve her bağlantı yeni bir anahtar kullanır. Telefondan oturumları izleyebilir (Claude Code ve Codex oturumlarını konuşma olarak da), yeni bir kabuk başlatabilir, izin sorularını kilit ekranından onaylayıp reddedebilir ve ilerlemeyi Canlı Etkinlik'te takip edebilirsiniz.

<!-- TODO: iPhone uygulaması herkese açılınca bağlantısını ekleyin (App Store ya da TestFlight) -->

### Yerleşik görünümler

Terminallerin yanında tuvalde web tarayıcısı, web sayfaları, notlar, beyaz tahta, dosya gezgini, video ve iOS Simülatörü ile Android emülatörü kutuları bulunur (Android'de `adb` ile dokunma, kaydırma ve yazma). Ajanlar isterseniz site başına izinle bir Safari penceresi kullanabilir.

## Kurulum

macOS 14 (Sonoma) ya da üstü gerekir.

**DMG.** Son sürümü [GitHub Releases](https://github.com/enmerasoftware/enterm/releases/latest) sayfasından indirin, DMG'yi açın ve Enterm'i Uygulamalar klasörüne sürükleyin. Sürümler Developer ID ile imzalı ve Apple onaylıdır (notarization), Sparkle ile kendilerini günceller.

**Homebrew.**

```bash
brew tap enmerasoftware/tap
brew trust enmerasoftware/tap   # Homebrew yeni bir depodan kurmadan önce onay ister
brew install --cask enterm
```

Ardından kullanmak istediğiniz ajanları (örneğin Claude Code ya da Codex) üreticilerinin anlattığı şekilde kurun. Enterm onları `PATH` üzerinde bulur.

## Kaynaktan derleme

`/Applications/Xcode.app` konumunda Xcode kurulu olmalı.

```bash
scripts/bundle.sh release
open build/release-$(git rev-parse --short HEAD)/Enterm.app
```

Testleri çalıştırmak için:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`DEVELOPER_DIR`, `xcode-select` Komut Satırı Araçları'na ayarlı olsa bile Swift'i testlerin ihtiyaç duyduğu tam Xcode araç zincirine yönlendirir. Yerel deneme için hata ayıklama derlemesi: `scripts/bundle.sh debug build/test`.

Depo yapısı:

- `Sources/EntermCore`: AppKit, UIKit ya da SwiftUI almayan çekirdek; iOS uygulaması bunun üzerine kurulur.
- `Sources/entermd`: pseudo terminallerin sahibi olan oturum servisi.
- `Sources/enterm`: kabuk entegrasyonu ve kancalar için küçük bir komut, ayrıca yerel MCP köprüsü.
- `Sources/EntermApp`: macOS uygulaması. Tuval ve terminaller AppKit, sayfa ve diyaloglar SwiftUI.
- `enterm-ios/`, `relay/`: iPhone uygulaması ve şifreli aktarım servisi.
- `skills/`: hazır beceri paketleri.

Bakımcı notları (iç yapı, test sürücüsü, sürüm yayınlama) [docs/MAINTAINERS.md](docs/MAINTAINERS.md) içinde.

## Gizlilik ve güvenlik

- **Ayar dosyası değişmez.** Enterm `~/.zshrc`, `~/.claude`, `~/.codex` ya da başka bir ayar dosyasına yazmaz. Entegrasyon başlatma argümanları ve ortam değişkenleriyle gelir.
- **Token yok.** Abonelik token'larınız resmi programın içinde kalır, Enterm'e hiç gelmez. İkinci bir hesap `CLAUDE_CONFIG_DIR` ya da `CODEX_HOME` ile programın kendisinde durur.
- **Uçtan uca şifreli telefon.** Eşleşme X25519 ve altı haneli karşılaştırma kullanır; aktarım servisi yalnız şifreli bayt taşır.
- **Varsayılan olarak yerel.** Oturumlar, dökümler ve MCP köprüsü Mac'inizde kalır. Enterm'in kendisi yalnız gördüğünüz işler için internete çıkar: güncelleme denetimi, istediğinizde dikte modeli ya da bir ajanın resmi kurulumu, açtığınız web sayfaları ve telefon eşleştirdiyseniz aktarım servisinden geçen şifreli trafik. Ajanlar kendi üreticileriyle düz terminalde olduğu gibi konuşur.
- **Görünen izinler.** Varsayılan olarak her program kendi sorularını düz terminaldeki gibi sorar; daha sıkı şablonlarda kararı Enterm'in yetki kartı verir.

Güvenlik açıklarını lütfen gizli bildirin, bkz. [SECURITY.md](SECURITY.md).

## Diller

Arayüz İngilizce ve Türkçedir; Mac'inizin dilini ya da Ayarlar'daki seçimi izler.

Kod Türkçe yazılır, İngilizce ise Türkçe kaynak metinle anahtarlanmış bir tablodur: [`Resources/en.json`](Resources/en.json). Kurulan metinde parçalar için `%@` kullanılır (`"Ekip %@"` → `"Team %@"`). Ekrandaki metni ekledikten ya da değiştirdikten sonra `scripts/strings.py` çalıştırın: İngilizcesi olmayan her metni listeler, CI da aynı denetimi yapar. Ekran metni olmayan dizgiler (komutlar, tanımlayıcılar) `Resources/en-same.json` dosyasına girer.

Üçüncü bir dil eklemek `en.json` yanında yeni bir tablo ve paketleme adımında ve dil listesinde küçük bir değişiklik demektir; lütfen önce bir issue açın, birlikte kuralım. Ayrıntılar [CONTRIBUTING.md](CONTRIBUTING.md#text-on-screen) içinde.

## Katkı

Issue ve pull request'ler İngilizce ya da Türkçe açılabilir. İlk katkı için en kolayı yeni bir beceridir. Önce [CONTRIBUTING.md](CONTRIBUTING.md) dosyasını okuyun.

## Lisans

MIT, bkz. [LICENSE](LICENSE).
