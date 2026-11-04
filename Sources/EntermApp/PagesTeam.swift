import AppKit
import EntermCore
import SwiftUI

// MARK: Team setup

struct TeamSetupPage: View {
    @ObservedObject var model = AppModel.shared
    @State private var step = 1
    @State private var brief = ""
    @State private var templateKey = "software"
    @State private var members: [TeamMember] = []
    @State private var folder = ""
    var body: some View {
        PageFrame(title: "Ekibini Kur · Adım \(step) / 2", wide: step == 2) {
            if step == 1 { request } else { proposal }
        }
        .onAppear { folder = model.focusedInfo?.cwd ?? NSHomeDirectory() }
    }

    private var request: some View {
        VStack(alignment: .leading, spacing: 16) {
            T("Projeyi Bir Cümleyle Anlatın", bold: true)
            EntermField(placeholder: "> Kupon ve iade akışını düzeltip test edelim", text: $brief)
            T("Ya Da Şablon Seçin", bold: true)
            Panel {
                templateRow("software", "Yazılım", "Yönetici, Geliştirici, Test, İnceleme")
                templateRow("marketing", "Pazarlama", "Yönetici, Strateji, Metin, Sosyal Medya")
                templateRow("company", "Tam Şirket", "Yazılım, Tasarım, İçerik, Pazarlama, Çeviri")
                templateRow("empty", "Boş", "Yalnız Yönetici, Kalanını Siz Eklersiniz")
            }
            Dim("Klasör: \(model.displayPath(folder))")
            HStack {
                Btn("Vazgeç", kind: .plain, key: "Esc") { model.page = nil }
                Btn("Kadro Öner", kind: .primary, key: "⏎") {
                    members = Team.template(templateKey)
                    step = 2
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
                Dim("Onayınız Olmadan Hiçbir Ajan Başlamaz")
            }
        }
    }

    private func templateRow(_ key: String, _ title: String, _ note: String) -> some View {
        MenuRow(title: title, note: note, key: templateKey == key ? "Seçili" : "", selected: templateKey == key) { templateKey = key }
    }

    private var proposal: some View {
        VStack(alignment: .leading, spacing: 16) {
            T("Kadro Önerisi", bold: true)
            Panel {
                ForEach($members) { $member in
                    HStack(spacing: 8) {
                        EntermField(placeholder: "Ad", text: $member.name).frame(width: 110)
                        EntermField(placeholder: "Rol", text: $member.role).frame(width: 130)
                        Picker("", selection: $member.tool) {
                            ForEach([ToolKind.claude, .codex, .antigravity], id: \.self) { Text(ToolCatalog.shared.pickerTitle($0)).font(Theme.swiftFont()).tag($0) }
                        }
                        .frame(width: 140)
                        EntermField(placeholder: "Model", text: $member.model).frame(width: 100)
                        Picker("", selection: $member.template) {
                            ForEach(PermissionTemplate.allCases) { Text($0.title).font(Theme.swiftFont()).tag($0) }
                        }
                        .frame(width: 140)
                        EntermField(placeholder: "Kaynaklar", text: $member.sources)
                        Btn("−", kind: .plain) { members.removeAll { $0.id == member.id } }
                    }
                    .padding(8)
                    Line()
                }
            }
            HStack {
                Btn("Üye Ekle +", kind: .plain) { members.append(TeamMember(name: "Üye \(members.count + 1)", role: "Yazılım")) }
                Spacer()
                Dim("Herkes \(members.first?.name ?? "yöneticiye") rapor verir. Yönetici raporları kontrol eder, kararları size getirir.")
            }
            Dim("Ekip El Kitabı: ekip/EL-KITABI.md yazılacak. Dosya sizindir, elle de düzenlersiniz. Boşta duran ajan token harcamaz.")
            HStack {
                Btn("Geri", kind: .plain) { step = 1 }
                Btn("Onayla Ve Ekibi Kur", kind: .primary, key: "⏎") { TeamBuilder.build(brief: brief, folder: folder, members: members) }
            }
        }
    }
}

enum TeamBuilder {
    /// Writes the handbook, starts each member with the official program, and draws report lines.
    static func build(brief: String, folder: String, members: [TeamMember]) {
        let model = AppModel.shared
        var team = Team()
        team.name = URL(fileURLWithPath: folder).lastPathComponent
        team.folder = folder
        team.brief = brief
        team.members = members
        team.managerID = members.first?.id
        let directory = URL(fileURLWithPath: folder).appendingPathComponent("ekip", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let handbook = directory.appendingPathComponent("EL-KITABI.md")
        if !FileManager.default.fileExists(atPath: handbook.path) {
            try? team.handbook().write(to: handbook, atomically: true, encoding: .utf8)
        }
        team.save()
        model.page = nil
        startMembers(team, index: 0)
    }

    private static func startMembers(_ team: Team, index: Int) {
        guard index < team.members.count else {
            finish(team)
            return
        }
        let member = team.members[index]
        let isManager = member.id == team.managerID
        let manager = team.members.first { $0.id == team.managerID }?.name ?? "yönetici"
        let intro = isManager
            ? "Sen \(member.name), \(member.role). ekip/EL-KITABI.md dosyasını oku. Kullanıcı iş verene kadar bekle, işi ekibe is_ver aracıyla dağıt, gelen raporları kontrol et, neyi kontrol edemediğini söyle."
            : "Sen \(member.name), \(member.role). ekip/EL-KITABI.md dosyasını oku. \(manager) iş verene kadar bekle. Bitince rapor_yaz aracıyla raporla."
        var plan = SettingsStore.shared.settings.defaultPlan
        plan.main = member.model
        plan.mainEffort = member.effort
        let arguments = member.tool == .antigravity ? "" : NotFoundActions.shellQuote(intro)
        ToolLauncher.start(member.tool, cwd: team.folder, name: member.name, extraArguments: arguments, group: team.name, plan: plan) { info in
            var updated = team
            updated.members[index].sessionID = info.id
            updated.save()
            var book = PermissionBook.load()
            book.cards[info.id] = member.template.card
            book.save()
            AppModel.shared.connection.send(WireMessage(op: "reloadPermissions"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { startMembers(updated, index: index + 1) }
        }
        if PowerCenter.shared.queue.contains(where: { $0.spec.name == member.name }) {
            startMembers(team, index: index + 1)
        }
    }

    private static func finish(_ team: Team) {
        let manager = team.members.first { $0.id == team.managerID }
        for member in team.members where member.id != team.managerID {
            guard let from = manager?.sessionID, let to = member.sessionID else { continue }
            LinkStore.shared.add(SessionLink(from: from, to: to, permission: .delegate, bothWays: true))
        }
        TeamStore.shared.reload()
        AppModel.shared.hint = "✓ Ekip Kuruldu. El Kitabı: ekip/EL-KITABI.md"
        AppModel.shared.connection.send(WireMessage(op: "reloadPermissions"))
    }
}

struct ManagerPage: View {
    @ObservedObject var store = TeamStore.shared
    @ObservedObject var model = AppModel.shared
    var body: some View {
        PageFrame(title: "Yönetici Görünümü", wide: true) {
            if let team = store.team {
                HStack {
                    T(team.name, bold: true)
                    Spacer()
                    Btn("El Kitabını Aç", kind: .plain) { model.page = .editor(team.folder + "/ekip/EL-KITABI.md") }
                }
                Panel {
                    ForEach(team.members) { member in
                        let info = model.sessions.first { $0.id == member.sessionID }
                        Row {
                            T(member.name, bold: true).frame(width: 120, alignment: .leading)
                            Dim("\(member.role) · \(member.tool.title)").frame(width: 240, alignment: .leading)
                            Dim(member.template.title)
                            Spacer()
                            if let info { StatusBadge(status: info.status) } else { Dim("Çalışmıyor") }
                        }
                        Line()
                    }
                }
                T("Bekleyen Kararlar", bold: true)
                let pending = model.sessions.compactMap(\.pendingApproval)
                if pending.isEmpty { Dim("Bekleyen karar yok.") }
                ForEach(pending) { request in
                    HStack {
                        T("◆ \(request.summary)", color: Theme.palette.need).lineLimit(1)
                        Spacer()
                        Btn("İzin Ver", kind: .primary) { Approvals.decide(id: request.id, decision: "allow") }
                        Btn("Reddet") { Approvals.decide(id: request.id, decision: "deny") }
                    }
                }
                T("Raporlar", bold: true)
                if team.reports.isEmpty { Dim("Henüz rapor gelmedi.") }
                ForEach(team.reports) { report in ReportCard(report: report) }
                Line()
                T("Kurallar", bold: true)
                VStack(alignment: .leading, spacing: 4) {
                    Dim("✓ Aynı dosyaya iki ajan aynı anda dokunmaz (Claude Code).")
                    Dim("✓ Alt ajanlar ekibe mesaj yazamaz (Claude Code).")
                    Dim("✓ Yetkisi olmayan iş başka ajana devredilemez.")
                    Dim("✓ Ajan mesajı onay sayılmaz. Karar düğmesine yalnız siz basarsınız.")
                    Dim("✓ Mesaj sınırına takılan rapor dosyada kalır: ekip/raporlar/")
                }
                T("Ağır İş Sırası", bold: true)
                HeavyQueueList()
            } else {
                Dim("Henüz ekip yok.")
                Btn("Ekibini Kur", kind: .primary) { model.page = .team }
            }
        }
    }
}

struct ReportCard: View {
    let report: AgentReport
    var body: some View {
        Panel {
            PanelHeader(title: "\(report.author) Raporu") { Dim("Ajan Raporu · \(report.at.formatted(date: .omitted, time: .shortened))") }
            VStack(alignment: .leading, spacing: 4) {
                line("Ne Değişti", report.changed)
                line("Ne Denendi", report.tried)
                line("Ne Denenmedi", report.notTried)
                line("Ne Bekliyor", report.waiting)
                if let file = report.file { Dim("Tamamı: \(file)") }
                Dim("Bu kart ajan mesajıdır, onay sayılmaz.")
            }
            .padding(12)
        }
    }
    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            T(title, bold: true).frame(width: 130, alignment: .leading)
            T(value)
        }
    }
}

// MARK: Board

struct BoardPage: View {
    @ObservedObject var store = BoardStore.shared
    @ObservedObject var model = AppModel.shared
    @State private var selected: String?
    @State private var newTitle = ""
    var body: some View {
        ZStack(alignment: .trailing) {
            PageFrame(title: nil, wide: true) {
                HStack {
                    T("Pano · \(store.board.cards.count) Kart", bold: true)
                    Spacer()
                    EntermField(placeholder: "Yeni Kart Başlığı", text: $newTitle)
                        .frame(width: 280)
                        .onSubmit(addCard)
                    Btn("+ Kart", kind: .primary) { addCard() }
                }
                if store.board.cards.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            T("Pano Boş", bold: true)
                            Dim("Kart yazın, üye olarak kendinizi ya da bir ajanı ekleyin. Ajan iş bitince raporla kartı Kontrolde'ye taşır, Bitti'ye yalnız siz alırsınız.")
                        }
                        .padding(12)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(BoardColumn.allCases) { column in
                        let cards = store.board.cards.filter { $0.column == column }.sorted { $0.priority > $1.priority }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                T(column.title, color: Theme.palette.text2, bold: true, style: .secondary)
                                Spacer()
                                T("\(cards.count)", color: Theme.palette.text3, style: .secondary)
                            }
                            .frame(height: 24)
                            .padding(.horizontal, 4)
                            ForEach(cards) { card in
                                Button { selected = card.id } label: { BoardCardView(card: card) }
                                    .buttonStyle(.plain)
                                    .onDrag { NSItemProvider(object: card.id as NSString) }
                            }
                            Spacer(minLength: 40)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(Color(Theme.palette.fill))
                        .cornerRadius(Theme.cornerFloat)
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            providers.first?.loadObject(ofClass: NSString.self) { item, _ in
                                guard let id = item as? String else { return }
                                DispatchQueue.main.async {
                                    store.change { board in
                                        if let index = board.cards.firstIndex(where: { $0.id == id }) { board.cards[index].column = column }
                                    }
                                    BoardDispatch.cardMoved(id: id, to: column)
                                }
                            }
                            return true
                        }
                    }
                }
            }
            if let selected, store.board.cards.contains(where: { $0.id == selected }) {
                CardDrawer(cardID: selected) { self.selected = nil }
                    .frame(width: 520)
                    .background(Color(Theme.palette.panel))
                    .overlay(alignment: .leading) { Rectangle().fill(Color(Theme.palette.line2)).frame(width: 1) }
            }
        }
    }
    private func addCard() {
        guard !newTitle.isEmpty else { return }
        let card = BoardCard(title: newTitle)
        store.change { $0.cards.append(card) }
        newTitle = ""
    }
}

struct BoardCardView: View {
    let card: BoardCard
    @ObservedObject var model = AppModel.shared
    var body: some View {
        Panel(border: card.column == .decision ? Theme.palette.need : Theme.palette.line2) {
            VStack(alignment: .leading, spacing: 4) {
                T(card.title, bold: true).lineLimit(2)
                Dim(card.members.isEmpty ? "Üye Yok" : card.members.joined(separator: ", ")).lineLimit(1)
                if let info = model.sessions.first(where: { $0.id == card.sessionID }) {
                    T("\(info.status.symbol) \(info.status.title)", color: Theme.palette.dim)
                }
                HStack {
                    if let due = card.due { Dim(due.formatted(date: .abbreviated, time: .omitted)) }
                    if card.priority > 0 { Dim("Öncelikli") }
                    if !card.comments.isEmpty { Dim("Yorum \(card.comments.count)") }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CardDrawer: View {
    let cardID: String
    let close: () -> Void
    @ObservedObject var store = BoardStore.shared
    @ObservedObject var model = AppModel.shared
    @State private var comment = ""
    private var card: BoardCard? { store.board.cards.first { $0.id == cardID } }
    private func edit(_ change: (inout BoardCard) -> Void) {
        store.change { board in
            if let index = board.cards.firstIndex(where: { $0.id == cardID }) { change(&board.cards[index]) }
        }
    }
    var body: some View {
        ScrollView {
            if let card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        T(card.title, bold: true)
                        Spacer()
                        Btn("Kapat", kind: .plain) { close() }
                    }
                    HStack {
                        T("Durum")
                        Picker("", selection: Binding(get: { card.column }, set: { value in edit { $0.column = value } })) {
                            ForEach(BoardColumn.allCases) { Text($0.title).font(Theme.swiftFont()).tag($0) }
                        }
                    }
                    HStack {
                        T("Son Tarih")
                        DatePicker("", selection: Binding(get: { card.due ?? Date() }, set: { value in edit { $0.due = value } }), displayedComponents: .date)
                            .labelsHidden()
                        if card.due != nil { Btn("Kaldır", kind: .plain) { edit { $0.due = nil } } }
                    }
                    HStack {
                        T("Öncelik")
                        Seg(options: [(0, "Normal"), (1, "Öncelikli")], value: Binding(get: { card.priority }, set: { value in edit { $0.priority = value } }))
                    }
                    T("Üyeler", bold: true)
                    HStack {
                        ForEach(card.members, id: \.self) { name in
                            Btn("\(name) ×", kind: .plain) { edit { $0.members.removeAll { $0 == name } } }
                        }
                        if !card.members.contains("Siz") { Btn("+ Siz · Kişi", kind: .plain) { edit { $0.members.append("Siz") } } }
                    }
                    T("Ajana Ata", bold: true)
                    ForEach(model.sessions.filter { $0.tool != .terminal }) { info in
                        Btn("\(model.title(for: info)) · \(info.status.title)", kind: .plain) { assign(info) }
                    }
                    HStack {
                        Btn("Yeni Claude Code Aç Ve Ata", kind: .primary) { startNew() }
                    }
                    Dim("Kart metni işe dönüşür. Güç sınırına gelinmişse iş Sırada bekler. Kartın yetkisi yoktur, ajanın kendi yetkisiyle çalışır.")
                    if let report = card.report { ReportCard(report: report) }
                    T("Yorumlar \(card.comments.count)", bold: true)
                    ForEach(card.comments.reversed()) { item in
                        VStack(alignment: .leading) {
                            Dim("\(item.author) · \(item.isAgent ? "Ajan" : "Kişi") · \(item.at.formatted(date: .omitted, time: .shortened))")
                            T(item.text)
                        }
                    }
                    HStack {
                        EntermField(placeholder: "Yorum Yazın", text: $comment)
                        Btn("Gönder") {
                            guard !comment.isEmpty else { return }
                            let text = comment
                            edit { $0.comments.append(CardComment(author: "Siz", isAgent: false, text: text)) }
                            comment = ""
                        }
                    }
                    Dim("Ajan yorumu onay sayılmaz. Karar düğmesine yalnız siz basarsınız.")
                    EntermField(placeholder: "Kart Metni: Ajana Verilecek Ayrıntı", text: Binding(get: { card.details }, set: { value in edit { $0.details = value } }))
                    Btn("Kartı Sil", kind: .danger) {
                        store.change { $0.cards.removeAll { $0.id == cardID } }
                        close()
                    }
                }
                .padding(16)
            }
        }
    }
    private func assign(_ info: SessionInfo) {
        guard let card else { return }
        let name = AppModel.shared.title(for: info)
        edit {
            $0.sessionID = info.id
            if !$0.members.contains(name) { $0.members.append(name) }
            $0.column = .doing
        }
        let text = "Pano Kartı: \(card.title). \(card.details) Bitince rapor_yaz aracıyla raporla.\r"
        model.connection.sendInput(number: info.number, bytes: Data(text.utf8))
    }
    private func startNew() {
        guard let card else { return }
        let prompt = "Pano Kartı: \(card.title). \(card.details) Bitince rapor_yaz aracıyla raporla."
        let title = card.title
        model.page = nil
        ToolLauncher.start(.claude, name: String(title.prefix(24)), extraArguments: NotFoundActions.shellQuote(prompt)) { info in
            BoardStore.shared.change { board in
                if let index = board.cards.firstIndex(where: { $0.id == cardID }) {
                    board.cards[index].sessionID = info.id
                    board.cards[index].members.append(info.name.isEmpty ? "Claude Code" : info.name)
                    board.cards[index].column = .doing
                }
            }
        }
    }
}

/// A card dropped on "Sürüyor" starts work: its agent gets the text, an unassigned card asks who.
enum BoardDispatch {
    static func cardMoved(id: String, to column: BoardColumn) {
        guard column == .doing, let card = BoardStore.shared.board.cards.first(where: { $0.id == id }) else { return }
        let model = AppModel.shared
        guard let session = model.sessions.first(where: { $0.id == card.sessionID }), session.tool != .terminal else {
            model.hint = "Kartı Bir Ajana Atayın: Karta Tıklayın"
            return
        }
        let text = "Pano Kartı: \(card.title). \(card.details) Bitince rapor_yaz aracıyla raporla.\r"
        model.connection.sendInput(number: session.number, bytes: Data(text.utf8))
    }
}
