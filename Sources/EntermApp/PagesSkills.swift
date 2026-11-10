import AppKit
import EntermCore
import SwiftUI

/// The preset skill packs, each switched on or off. Read from the app bundle when the page opens, never before.
struct SkillsSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    @State private var packs: [SkillPack] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Dim("Açtığınız paket yeni Claude Code oturumlarına verilir. Beceri işe uyunca kendiliğinden çalışır, adıyla da çağrılır: oturumda /video:subtitles gibi. ~/.claude klasörünüze hiçbir şey yazılmaz.")
                .fixedSize(horizontal: false, vertical: true)
            if packs.isEmpty {
                Panel {
                    SettingsLine(title: "Paket Bulunamadı", note: "Uygulama paketinde Resources/skills yok. Kaynaktan derlediyseniz scripts/bundle.sh ile yeniden derleyin.") { EmptyView() }
                }
            }
            ForEach(packs) { pack in
                Panel {
                    PanelHeader(title: Self.title(pack.id)) {
                        Seg(options: [(true, "Açık"), (false, "Kapalı")], value: Binding(
                            get: { store.settings.skillPacks.contains(pack.id) },
                            set: { on in
                                store.settings.skillPacks.removeAll { $0 == pack.id }
                                if on { store.settings.skillPacks.append(pack.id) }
                            }))
                    }
                    ForEach(pack.skills) { skill in
                        SkillRow(command: skill.command(pack: pack.id), summary: Self.summary(skill.description))
                    }
                }
            }
            Dim("Codex, Gemini ve Antigravity için şimdilik yok: bu programlar ek beceri klasörünü yalnız kendi ayar klasörlerinden okuyor, Enterm o klasörlere yazmaz.")
                .fixedSize(horizontal: false, vertical: true)
            Dim("Yeni beceri eklemek açık kaynak deposunda bir klasör ve bir SKILL.md dosyası kadar kolay: CONTRIBUTING.md.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            guard let executable = Bundle.main.executablePath,
                  let root = SkillPack.root(executable: executable, environment: ProcessInfo.processInfo.environment) else { return }
            packs = SkillPack.packs(in: root)
        }
    }

    static func title(_ id: String) -> String {
        switch id {
        case "code": return "Yazılım"
        case "video": return "Video"
        case "image": return "Görsel"
        default: return id.capitalized
        }
    }

    /// The part before "Use when": what the skill does. The rest is for the program, which picks skills by it.
    static func summary(_ description: String) -> String {
        description.components(separatedBy: " Use when").first ?? description
    }
}

private struct SkillRow: View {
    let command: String
    let summary: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            T(command, color: Theme.palette.text1, style: .secondary, weight: .semibold)
                .frame(width: 210, alignment: .leading)
                .textSelection(.enabled)
            Dim(summary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .settingsRow()
    }
}

/// Claude Code's own commands in Turkish. A row types its command into the focused Claude Code session, without Enter.
struct ClaudeCommandsSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared

    var body: some View {
        let target = model.focusedInfo.flatMap { $0.tool == .claude ? $0 : nil }
        VStack(alignment: .leading, spacing: 16) {
            Dim(target == nil
                ? "Bir Claude Code oturumu seçiliyken Yaz komutu o oturuma yazar, Enter'a siz basarsınız. Sürüme ve plana göre bazı komutlar görünmeyebilir; kesin liste oturumda / yazınca çıkar."
                : "Yaz, komutu \(model.title(for: target!)) oturumuna yazar; Enter'a siz basarsınız. Sürüme ve plana göre bazı komutlar görünmeyebilir.")
                .fixedSize(horizontal: false, vertical: true)
            Panel {
                PanelHeader(title: "Efor Seviyeleri") { Dim("/effort ya da --effort") }
                ForEach(ClaudeCommands.effortLevels, id: \.level) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        T(item.level, style: .secondary, weight: .semibold).frame(width: 90, alignment: .leading)
                        Dim(item.summary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let target, item.level != "ultracode" {
                            Btn("Yaz", kind: .plain) { type("/effort \(item.level)", into: target) }
                        }
                    }
                    .settingsRow()
                }
            }
            ForEach(ClaudeCommands.groups, id: \.self) { group in
                Panel {
                    PanelHeader(title: group) { EmptyView() }
                    ForEach(ClaudeCommands.all.filter { $0.group == group }) { command in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                T("/" + command.name, style: .secondary, weight: .semibold).textSelection(.enabled)
                                if !command.arguments.isEmpty { Dim(command.arguments) }
                            }
                            .frame(width: 210, alignment: .leading)
                            Dim(command.summary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if let target {
                                Btn("Yaz", kind: .plain) { type(command.typed, into: target) }
                            }
                        }
                        .settingsRow()
                    }
                }
            }
        }
    }

    private func type(_ text: String, into info: SessionInfo) {
        model.connection.sendInput(number: info.number, bytes: Data(text.utf8))
        model.hint = "Yazıldı: \(text.trimmingCharacters(in: .whitespaces))"
    }
}
