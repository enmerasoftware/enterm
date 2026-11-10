import Foundation

/// Claude Code's own slash commands, explained in Turkish. Checked against code.claude.com/docs/en/commands on 2026-11-10.
/// What a session really offers depends on its version and plan; its own `/` menu is the final word.
public struct ClaudeCommand: Equatable, Identifiable {
    public var name: String
    public var arguments: String
    public var summary: String
    public var group: String
    public var id: String { name }
    /// What goes into the terminal: the command and a space, never Enter, so the person finishes it.
    public var typed: String { "/\(name) " }
}

public enum ClaudeCommands {
    public static let groups = ["Model Ve Efor", "Bağlam Ve Bellek", "Oturum", "Kod Ve Git", "Araçlar Ve Eklentiler", "Ayarlar", "Hesap"]

    /// The effort levels, lowest to highest, as `/effort` and `--effort` take them.
    public static let effortLevels: [(level: String, summary: String)] = [
        ("low", "En hızlı ve en ucuz. Basit soru, küçük düzeltme."),
        ("medium", "Opus 5.5, Sonnet 5.5 ve Haiku 5.5'te varsayılan."),
        ("high", "Daha uzun düşünür. Çok dosyalı iş, zor hata."),
        ("xhigh", "Bunun da üstü. Opus 4.6 ve Sonnet 4.6'da yok, bir alta iner."),
        ("max", "En uzun düşünme. Yalnız bu oturum için geçerli, kaydedilmez."),
        ("ultracode", "xhigh ile birlikte uzun kodlama modu. Seviye değil, ayrı bir anahtar: /effort ultracode on."),
        ("auto", "Seviye göndermez; modelin kendi varsayılanı geçerli olur."),
    ]

    public static let all: [ClaudeCommand] = [
        ClaudeCommand(name: "effort", arguments: "[low|medium|high|xhigh|max|auto|status]", summary: "Düşünme seviyesini değiştirir. Kaydırıcıda Enter modele kaydeder, s yalnız bu oturuma uygular.", group: "Model Ve Efor"),
        ClaudeCommand(name: "model", arguments: "[model]", summary: "Modeli değiştirir ve varsayılan yapar.", group: "Model Ve Efor"),
        ClaudeCommand(name: "fast", arguments: "[on|off]", summary: "Hızlı modu açar ya da kapatır: aynı model, daha hızlı çıktı.", group: "Model Ve Efor"),
        ClaudeCommand(name: "output-style", arguments: "[stil]", summary: "Yanıt biçimini listeler ya da değiştirir.", group: "Model Ve Efor"),

        ClaudeCommand(name: "context", arguments: "[all]", summary: "Bağlamın nelerle dolduğunu renkli bir tabloyla gösterir, öneri verir.", group: "Bağlam Ve Bellek"),
        ClaudeCommand(name: "compact", arguments: "[talimat]", summary: "Konuşmayı özetleyip bağlamda yer açar. Neyin korunacağını yazabilirsiniz.", group: "Bağlam Ve Bellek"),
        ClaudeCommand(name: "clear", arguments: "", summary: "Konuşmayı sıfırlar, temiz bağlamla yeni başlar.", group: "Bağlam Ve Bellek"),
        ClaudeCommand(name: "memory", arguments: "", summary: "CLAUDE.md dosyalarını ve otomatik belleği düzenler.", group: "Bağlam Ve Bellek"),
        ClaudeCommand(name: "init", arguments: "", summary: "Proje için CLAUDE.md oluşturur.", group: "Bağlam Ve Bellek"),
        ClaudeCommand(name: "add-dir", arguments: "<yol>", summary: "Bu oturuma bir çalışma klasörü daha ekler.", group: "Bağlam Ve Bellek"),

        ClaudeCommand(name: "resume", arguments: "[oturum]", summary: "Eski bir konuşmaya kimlikle ya da adla döner, boş bırakılırsa seçici açar. Diğer adı /continue.", group: "Oturum"),
        ClaudeCommand(name: "rewind", arguments: "", summary: "Kodu ve konuşmayı önceki bir noktaya geri alır. Diğer adları /checkpoint, /undo.", group: "Oturum"),
        ClaudeCommand(name: "export", arguments: "[dosya]", summary: "Konuşmayı metin olarak dışa aktarır.", group: "Oturum"),
        ClaudeCommand(name: "tasks", arguments: "", summary: "Arka planda çalışan işleri gösterir. Diğer adı /bashes.", group: "Oturum"),
        ClaudeCommand(name: "loop", arguments: "[aralık] [istem]", summary: "Bir istemi belirli aralıkla tekrar çalıştırır.", group: "Oturum"),
        ClaudeCommand(name: "usage", arguments: "", summary: "Oturum maliyeti, plan limitleri ve etkinlik. Diğer adları /cost, /stats.", group: "Oturum"),
        ClaudeCommand(name: "help", arguments: "", summary: "Bu sürümdeki tüm komutları listeler.", group: "Oturum"),

        ClaudeCommand(name: "code-review", arguments: "[low…max|ultra] [--fix] [--comment] [pr|dal|yol]", summary: "Değişiklikleri hata için inceler. Diğer adı /review.", group: "Kod Ve Git"),
        ClaudeCommand(name: "security-review", arguments: "", summary: "Daldaki değişikliği ana dala göre güvenlik açısından inceler.", group: "Kod Ve Git"),
        ClaudeCommand(name: "install-github-app", arguments: "", summary: "Depoya Claude GitHub uygulamasını kurar.", group: "Kod Ve Git"),

        ClaudeCommand(name: "skills", arguments: "", summary: "Yüklü becerileri listeler. Enterm'in hazır becerileri de burada görünür.", group: "Araçlar Ve Eklentiler"),
        ClaudeCommand(name: "reload-skills", arguments: "", summary: "Beceri klasörlerini yeniden tarar.", group: "Araçlar Ve Eklentiler"),
        ClaudeCommand(name: "plugin", arguments: "[alt komut]", summary: "Eklentileri yönetir.", group: "Araçlar Ve Eklentiler"),
        ClaudeCommand(name: "reload-plugins", arguments: "[--force]", summary: "Eklentileri yeniden başlatmadan yükler.", group: "Araçlar Ve Eklentiler"),
        ClaudeCommand(name: "mcp", arguments: "[reconnect|enable|disable <sunucu|all>]", summary: "MCP sunucularını gösterir ve yönetir.", group: "Araçlar Ve Eklentiler"),
        ClaudeCommand(name: "agents", arguments: "", summary: "Alt ajanları oluşturma ve düzenleme.", group: "Araçlar Ve Eklentiler"),
        ClaudeCommand(name: "hooks", arguments: "", summary: "Kanca ayarlarını gösterir.", group: "Araçlar Ve Eklentiler"),
        ClaudeCommand(name: "ide", arguments: "", summary: "Editör bağlantısını yönetir.", group: "Araçlar Ve Eklentiler"),

        ClaudeCommand(name: "config", arguments: "[anahtar=değer]", summary: "Ayarlar ekranı. Diğer adı /settings.", group: "Ayarlar"),
        ClaudeCommand(name: "permissions", arguments: "", summary: "İzin ver, sor ve yasakla kuralları.", group: "Ayarlar"),
        ClaudeCommand(name: "sandbox", arguments: "", summary: "Korumalı alan modunu açar ya da kapatır.", group: "Ayarlar"),
        ClaudeCommand(name: "statusline", arguments: "", summary: "Durum satırını ayarlar. Enterm kendi satırını gösterir, sizinkini de korur.", group: "Ayarlar"),
        ClaudeCommand(name: "terminal-setup", arguments: "", summary: "Shift+Enter ile yeni satır tuşunu kurar.", group: "Ayarlar"),
        ClaudeCommand(name: "doctor", arguments: "", summary: "Kurulumu denetler, düzeltebileceğini düzeltir. Diğer adı /checkup.", group: "Ayarlar"),
        ClaudeCommand(name: "release-notes", arguments: "", summary: "Sürüm notlarını gösterir.", group: "Ayarlar"),

        ClaudeCommand(name: "login", arguments: "", summary: "Hesaba giriş yapar.", group: "Hesap"),
        ClaudeCommand(name: "logout", arguments: "", summary: "Hesaptan çıkar.", group: "Hesap"),
        ClaudeCommand(name: "privacy-settings", arguments: "", summary: "Gizlilik ayarları. Pro, Max ve Ultra planlarında.", group: "Hesap"),
        ClaudeCommand(name: "upgrade", arguments: "", summary: "Plan yükseltme sayfasını açar.", group: "Hesap"),
    ]
}
