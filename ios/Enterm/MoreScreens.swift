import EntermCore
import SwiftUI

/// The back line every opened screen shares.
struct RouteHeader: View {
    @EnvironmentObject var model: PhoneModel
    let back: String
    var trailing: String?
    var asksApproval = false
    var body: some View {
        HStack {
            Button { if !model.route.isEmpty { model.route.removeLast() } } label: { BackLabel(title: back) }
                .buttonStyle(.plain)
            Spacer()
            if asksApproval {
                HStack(spacing: 6) {
                    Image(systemName: "diamond.fill").font(.caption2).foregroundColor(Palette.need)
                    Txt("Onay İstiyor", color: Palette.need, style: .footnote, weight: .semibold).lineLimit(1)
                }
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .frame(minHeight: 24)
                .background(Palette.need.opacity(0.16))
                .cornerRadius(6)
            } else if let trailing {
                Txt(trailing, color: Palette.text2, style: .footnote, weight: .medium).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Palette.surface1)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }
}

private struct GroupedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var navGrouped: Bool {
        get { self[GroupedKey.self] }
        set { self[GroupedKey.self] = newValue }
    }
}

/// Rows that belong together share one group, with a hair between them.
struct NavGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .environment(\.navGrouped, true)
            .background(Palette.surface1)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hair))
            .cornerRadius(12)
    }
}

struct NavRow: View {
    @Environment(\.navGrouped) private var grouped
    @ScaledMetric private var iconBox: CGFloat = 28
    let title: String
    var icon: String?
    let action: () -> Void
    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon { Image(systemName: icon).foregroundColor(Palette.text2).frame(width: iconBox) }
                Txt(title).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(Palette.text3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(grouped ? Color.clear : Palette.surface1)
            .overlay(alignment: .top) { if grouped { Rectangle().fill(Palette.hair).frame(height: 1) } }
            .cornerRadius(grouped ? 0 : 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One selection style: neutral. Yellow is for the main action, approvals and the tab count.
struct Choice<Value: Hashable>: View {
    @Environment(\.dynamicTypeSize) private var size
    let options: [(Value, String)]
    @Binding var value: Value
    var body: some View {
        let layout = size.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(options, id: \.0) { option in
                let on = option.0 == value
                Button { value = option.0 } label: {
                    Txt(option.1, color: on ? Palette.text1 : Palette.text2, style: .subheadline, weight: on ? .medium : .regular)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? Palette.fillSelected : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Palette.fill)
        .cornerRadius(8)
    }
}

struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.text3), axis: .vertical)
            .font(.body)
            .foregroundColor(Palette.text1)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Palette.field)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hair2))
    }
}

/// What a command looks like before it runs: all of it, never cut.
struct CommandText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mono)
            .foregroundColor(Palette.terminalText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.terminal)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hair2))
    }
}

/// Loads an answer from the Mac and says plainly when it cannot.
struct Loaded<T: Decodable, Content: View>: View {
    @EnvironmentObject var model: PhoneModel
    let call: PhoneCall
    let type: T.Type
    @ViewBuilder let content: (T, @escaping () -> Void) -> Content
    @State private var value: T?
    @State private var problem: String?
    @State private var generation = 0

    var body: some View {
        Group {
            if let value {
                content(value) { generation += 1 }
            } else if let problem {
                Card {
                    Txt(problem, color: Palette.err)
                    ActionButton("Tekrar Dene") {
                        self.problem = nil
                        generation += 1
                    }
                }
                .padding(16)
            } else {
                DimTxt("Bilgisayardan Okunuyor").padding(16)
            }
        }
        .task(id: generation) {
            switch await model.call(call, as: type) {
            case .success(let answer):
                value = answer
                problem = nil
            case .failure(let error):
                problem = error.message
            }
        }
    }
}

/// 1.4T and 1.5T, on the session the program was asked for in.
struct FoundCardView: View {
    @EnvironmentObject var model: PhoneModel
    let info: SessionInfo
    @State private var card: PhoneFoundCard?
    @State private var dismissed = false

    private var command: String? {
        if info.status == .notFound { return info.tool.command }
        return nil
    }

    var body: some View {
        // A stack, not a group: an empty group is no view at all, and its task would never run.
        VStack(spacing: 0) {
            if let card, !dismissed {
                Card {
                    Txt(card.title, bold: true)
                    CommandText(text: card.command)
                    DimTxt(card.note).fixedSize(horizontal: false, vertical: true)
                    ActionButton(card.button, style: .primary) {
                        Task {
                            guard await PhoneAuth.confirm("Komutu bilgisayarda çalıştırmak için doğrulayın.") else { return }
                            model.input(info.number, Data((card.command + "\r").utf8))
                            dismissed = true
                        }
                    }
                    ActionButton("Vazgeç", style: .plain) { dismissed = true }
                }
            }
        }
        .task(id: "\(info.status.rawValue)-\(model.missingProgram ?? "")") {
            guard let name = command ?? (model.openSession == info.number ? model.missingProgram : nil) else { return }
            dismissed = false
            if case .success(let answer) = await model.call(PhoneCall("foundCard", number: info.number, args: ["command": name]), as: PhoneFoundCard.self) {
                card = answer
            }
            model.missingProgram = nil
        }
    }
}

struct RouteScreen: View {
    let route: PhoneRoute
    var body: some View {
        Group {
            switch route {
            case .details(let number): DetailsScreen(number: number)
            case .changes(let number): ChangesScreen(number: number)
            case .diff(let number, let path): DiffScreen(number: number, path: path)
            case .browser(let number): BrowserScreen(number: number)
            case .linkTarget(let number): LinkTargetScreen(number: number)
            case .linkPermission(let from, let to): LinkPermissionScreen(from: from, to: to)
            case .messages(let number): MessagesScreen(number: number)
            case .card(let number): PermissionCardScreen(number: number)
            case .limit(let number): LimitScreen(number: number)
            case .accounts: AccountsScreen()
            case .accountAdd: AccountAddScreen()
            case .cost: CostScreen()
            case .power: PowerScreen()
            case .teamStart: TeamStartScreen()
            case .teamRoster: TeamRosterScreen()
            case .teamDecisions: TeamDecisionsScreen()
            case .report(let id): ReportScreen(id: id)
            case .newOptions: NewOptionsScreen()
            case .install(let tool): InstallScreen(tool: tool)
            case .approval(let id): ApprovalDetailScreen(id: id)
            case .queued(let id): QueuedScreen(id: id)
            case .limitOpened: LimitOpenedScreen()
            case .resumeFailed(let number): ResumeFailedScreen(number: number)
            case .codexLimit(let number): CodexLimitScreen(number: number)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
    }
}

// MARK: Details

/// 4.2T and 4.6T: what the session runs on, and where each of its tools opens.
struct DetailsScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Oturum")
            if let info = model.session(number) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Card {
                            HStack {
                                Txt(model.title(info), bold: true)
                                Spacer()
                                StatusText(info: info)
                            }
                            DimTxt(info.cwd)
                        }
                        if info.tool != .terminal {
                            Card {
                                Txt("Model Ve Akış · \(info.tool.title)", bold: true)
                                DimTxt(flow(info))
                                ForEach(info.subagents ?? []) { agent in
                                    HStack {
                                        Txt(agent.type ?? "Alt Ajan").lineLimit(1)
                                        Spacer()
                                        DimTxt(agent.running ? "● Çalışıyor" : "✓ Bitti")
                                    }
                                }
                                if info.tool == .codex { DimTxt("Codex alt ajan bilgisi kısmen gelir.") }
                                LimitLines(limit: info.limit)
                            }
                        }
                        NavGroup {
                            NavRow("Değişiklikler", icon: "arrow.triangle.branch") { model.route.append(.changes(number)) }
                            NavRow("Tarayıcı", icon: "safari") { model.route.append(.browser(number)) }
                            NavRow("Bağlantı Kur", icon: "link") { model.route.append(.linkTarget(number)) }
                            NavRow("Mesajlar", icon: "bubble.left.and.bubble.right") { model.route.append(.messages(number)) }
                            if info.tool != .terminal { NavRow("Yetki Kartı", icon: "checkmark.shield") { model.route.append(.card(number)) } }
                        }
                        ActionButton("Oturumu Kapat") {
                            model.close(number)
                            model.route = []
                            model.openSession = nil
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
    private func flow(_ info: SessionInfo) -> String {
        var parts: [String] = []
        if let name = info.model { parts.append(name) }
        if let effort = info.effort { parts.append("Efor: \(effort)") }
        if let tokens = info.contextTokens { parts.append("\(PhoneCost.short(tokens)) Token") }
        return parts.isEmpty ? "Henüz Bilinmiyor" : parts.joined(separator: " · ")
    }
}

struct LimitLines: View {
    @Environment(\.dynamicTypeSize) private var size
    let limit: LimitSnapshot?
    var body: some View {
        if let window = limit?.fiveHour { line("5 Saatlik", window) }
        if let window = limit?.sevenDay { line("7 Günlük", window) }
    }
    @ViewBuilder private func line(_ title: String, _ window: LimitWindow) -> some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                DimTxt("\(title) %\(Int(window.usedPercent))")
                if let resets = window.resetsAt { DimTxt(resets.turkish()) }
            }
        } else {
            HStack {
                DimTxt("\(title) %\(Int(window.usedPercent))")
                Spacer()
                if let resets = window.resetsAt { DimTxt(resets.turkish()) }
            }
        }
    }
}

// MARK: Changes

/// 4.3T: what the session changed, file by file, and a note back to it.
struct ChangesScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    @State private var note = ""
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: model.session(number).map { model.title($0) } ?? "Oturum")
            Loaded(call: PhoneCall("changes", number: number), type: PhoneChanges.self) { changes, reload in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !changes.isRepository {
                            DimTxt("Bu klasör bir git deposu değil.")
                        } else {
                            HStack {
                                Txt("\(changes.files.count) Dosya", bold: true)
                                Spacer()
                                DimTxt(changes.branch)
                            }
                            if changes.files.isEmpty { DimTxt("Değişiklik Yok.") }
                            ForEach(changes.files) { file in
                                Button { model.route.append(.diff(number, file.path)) } label: {
                                    HStack {
                                        Txt(file.path).lineLimit(1).truncationMode(.head)
                                        Spacer()
                                        if file.added > 0 { Txt("+\(file.added)", color: Palette.add) }
                                        if file.removed > 0 { Txt("-\(file.removed)", color: Palette.err) }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Palette.surface1)
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            ActionButton("Yenile", style: .plain, action: reload)
                        }
                        DimTxt("Oturuma Not Bırak")
                        InputField(placeholder: "Not yazın", text: $note)
                        DimTxt("Oturuma sizin yazınız olarak gider.")
                        ActionButton("Gönder") {
                            guard !note.isEmpty else { return }
                            model.input(number, Data((note + "\r").utf8))
                            note = ""
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct DiffScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    let path: String
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Değişiklikler", trailing: URL(fileURLWithPath: path).lastPathComponent)
            Loaded(call: PhoneCall("diff", number: number, args: ["path": path]), type: String.self) { text, _ in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                            Text(String(line))
                                .font(.mono)
                                .foregroundColor(color(line))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
    private func color(_ line: Substring) -> Color {
        if line.hasPrefix("+") { return Palette.add }
        if line.hasPrefix("-") { return Palette.err }
        if line.hasPrefix("@@") { return Palette.dim }
        return Palette.fg
    }
}

// MARK: Browser

/// 5.1T: the picture comes from the Mac, a picture a second while this screen is open.
struct BrowserScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    @State private var state: PhoneBrowser?
    @State private var problem: String?
    @State private var address = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: model.session(number).map { model.title($0) } ?? "Oturum",
                        trailing: state?.agent != nil && state?.userHasControl == false ? "● Kullanıyor" : nil)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    InputField(placeholder: "localhost:5173", text: $address)
                    ActionButton("Aç") {
                        Task { _ = await model.call(PhoneCall("browserOpen", args: ["address": address]), as: PhoneNothing.self) }
                    }
                    .frame(width: 72)
                }
                if let problem { Txt(problem, color: Palette.err) }
                if let failure = state?.failure { Txt(failure, color: Palette.err) }
                if let data = state?.image, let image = UIImage(data: data) {
                    GeometryReader { geometry in
                        ZoomableImage(image: image, onTap: { point in
                            guard state?.userHasControl == true else { return }
                            let x = String(Double(point.x / geometry.size.width))
                            let y = String(Double(point.y / geometry.size.height))
                            Task { _ = await model.call(PhoneCall("browserTap", args: ["x": x, "y": y]), as: PhoneNothing.self) }
                        }, onScroll: { distance in
                            guard state?.userHasControl == true else { return }
                            scroll(Double(-distance / geometry.size.height))
                        })
                    }
                } else {
                    DimTxt(state?.isOpen == true ? "Görüntü Bekleniyor" : "Tarayıcı Kapalı. Adres Yazıp Açın.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line2))
                }
                DimTxt("Görüntü bilgisayardan gelir. Devralınca parmakla kaydırın. İki parmakla yakınlaştırın.")
                if let agent = state?.agent, let step = state?.lastStep, state?.userHasControl == false {
                    DimTxt("\(agent): \(step)").lineLimit(2)
                }
                if state?.userHasControl == true {
                    HStack {
                        InputField(placeholder: "Odaktaki alana yaz", text: $text)
                        ActionButton("Yaz") {
                            let value = text
                            text = ""
                            Task { _ = await model.call(PhoneCall("browserType", args: ["text": value]), as: PhoneNothing.self) }
                        }
                        .frame(width: 72)
                    }
                    ActionButton("Ajana Geri Ver") { control(false) }
                } else {
                    ActionButton("Devral", style: .primary) { control(true) }
                }
            }
            .padding(12)
        }
        .task {
            // Stops by itself when the screen goes away.
            while !Task.isCancelled {
                switch await model.call(PhoneCall("browser"), as: PhoneBrowser.self) {
                case .success(let answer):
                    state = answer
                    problem = nil
                    if address.isEmpty, answer.isOpen { address = answer.address }
                case .failure(let error):
                    problem = error.message
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func control(_ on: Bool) {
        Task { _ = await model.call(PhoneCall("browserControl", args: ["on": on ? "1" : "0"]), as: PhoneNothing.self) }
    }

    private func scroll(_ amount: Double) {
        Task { _ = await model.call(PhoneCall("browserScroll", args: ["by": String(amount)]), as: PhoneNothing.self) }
    }
}

struct ZoomableImage: View {
    let image: UIImage
    let onTap: (CGPoint) -> Void
    let onScroll: (CGFloat) -> Void
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .scaleEffect(scale * pinch, anchor: .top)
            .gesture(MagnificationGesture().updating($pinch) { value, state, _ in state = value }.onEnded { scale = max(1, min(4, scale * $0)) })
            .simultaneousGesture(SpatialTapGesture().onEnded { onTap($0.location) })
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { onScroll($0.translation.height) })
            .clipped()
    }
}

// MARK: Links

/// 6.1T: no dragging on a phone. A tap on the box it should link to.
struct LinkTargetScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(back: "Vazgeç", trailing: "Adım 1 / 2")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Txt("\(model.session(number).map { model.title($0) } ?? "") Kime Bağlansın?", bold: true)
                    DimTxt("Sürükleme yok: kutuya dokunun.")
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.sessions.filter { $0.number != number }) { info in
                            Button { model.route.append(.linkPermission(number, info.number)) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Txt(model.title(info), bold: true).lineLimit(1)
                                    StatusText(info: info).lineLimit(1)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                                .background(Palette.panel)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hair))
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if model.sessions.count < 2 { DimTxt("Bağlanacak Başka Oturum Yok.") }
                    Loaded(call: PhoneCall("links"), type: [PhoneLink].self) { links, reload in
                        VStack(alignment: .leading, spacing: 8) {
                            if !links.isEmpty { Txt("Bağlantılar", bold: true) }
                            ForEach(links) { link in
                                Card {
                                    Txt("\(link.fromName) \(link.bothWays ? "↔" : "→") \(link.toName)", bold: true)
                                    DimTxt(link.permission.title)
                                    ActionButton("Bağlantıyı Sil") {
                                        Task {
                                            _ = await model.call(PhoneCall("linkRemove", args: ["id": link.id]), as: PhoneNothing.self)
                                            reload()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

/// 6.2T
struct LinkPermissionScreen: View {
    @EnvironmentObject var model: PhoneModel
    let from: UInt32
    let to: UInt32
    @State private var permission = LinkPermission.delegate
    @State private var bothWays = false
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(back: "Geri", trailing: "Adım 2 / 2")
            VStack(alignment: .leading, spacing: 12) {
                Txt("\(model.session(from).map { model.title($0) } ?? "") → \(model.session(to).map { model.title($0) } ?? "")", bold: true)
                Txt("Ne Yapabilsin?", bold: true)
                ForEach(LinkPermission.allCases) { option in
                    Button { permission = option } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Txt(permission == option ? "●" : "○")
                            VStack(alignment: .leading, spacing: 2) {
                                Txt(option.title)
                                DimTxt(option.note)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                DimTxt("Yön")
                Choice(options: [(false, "Tek Yön"), (true, "Çift Yön")], value: $bothWays)
                DimTxt("Bağlantı yetki vermez, ajan mesajı onay sayılmaz.")
                if let problem { Txt(problem, color: Palette.err) }
                Spacer()
                ActionButton("Bağla", style: .primary) {
                    Task {
                        let args = ["to": String(to), "permission": permission.rawValue, "both": bothWays ? "1" : "0"]
                        switch await model.confirmedCall("Bağlantı kurmak için doğrulayın.", PhoneCall("linkAdd", number: from, args: args), as: PhoneNothing.self) {
                        case .success:
                            model.route.removeAll { if case .linkTarget = $0 { return true }; if case .linkPermission = $0 { return true }; return false }
                        case .failure(let error):
                            problem = error.message
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

/// 7.1T
struct MessagesScreen: View {
    let number: UInt32
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: model.session(number).map { model.title($0) } ?? "Oturum", trailing: "Mesajlar")
            Loaded(call: PhoneCall("messages", number: number), type: [AgentMail].self) { mails, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if mails.isEmpty { DimTxt("Henüz Mesaj Yok.") }
                        ForEach(mails) { mail in
                            Card {
                                HStack {
                                    Txt("\(mail.fromName) → \(mail.toName)", bold: true).lineLimit(1)
                                    Spacer()
                                    DimTxt(mail.at.turkish(date: .omitted))
                                }
                                Txt(mail.text)
                                if mail.claimedApproval {
                                    Txt("✕ Onay Sayılmadı", color: Palette.err, bold: true)
                                    DimTxt("Ajan mesajı onay değildir. İstek size düştü.")
                                    if let id = model.session(number)?.pendingApproval?.id {
                                        ActionButton("Onay İsteğini Aç", style: .primary) { model.route.append(.approval(id)) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

/// 8.3T
struct PermissionCardScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    @State private var open: PermissionCategory?
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: model.session(number).map { model.title($0) } ?? "Oturum", trailing: "Yetki Kartı")
            Loaded(call: PhoneCall("card", number: number), type: PermissionCard.self) { card, reload in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(PermissionCategory.allCases) { category in
                            Button { open = open == category ? nil : category } label: {
                                HStack {
                                    Txt(category.title)
                                    Spacer()
                                    DimTxt("\(card.mode(category).title) ›")
                                }
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Palette.surface1)
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if open == category {
                                Choice(options: PermissionMode.allCases.map { ($0, $0.title) }, value: Binding(
                                    get: { card.mode(category) },
                                    set: { (mode: PermissionMode) in
                                        Task { @MainActor in
                                            _ = await model.setPermission(number, category: category, from: card.mode(category), to: mode)
                                            open = nil
                                            reload()
                                        }
                                    }))
                            }
                        }
                        DimTxt("Satıra dokununca üç seçenek açılır. Yetkiyi genişletmek doğrulama ister.")
                    }
                    .padding(16)
                }
            }
        }
    }
}

/// 9.4T: the same choices as on the Mac. The account changes only by this choice.
struct LimitScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Oturum", trailing: "■ Limit Doldu")
            Loaded(call: PhoneCall("limitChoices", number: number), type: [PhoneChoice].self) { choices, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        DimTxt("İş kaybolmadı, oturum bekliyor.")
                        ForEach(choices) { choice in
                            Button {
                                Task {
                                    let result = await model.confirmedCall("Hesap değişimi için doğrulayın.", PhoneCall("limitRun", args: ["index": String(choice.id)]), as: PhoneNothing.self)
                                    if case .success = result {
                                        model.route = []
                                        model.openSession = nil
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Txt(choice.title, bold: true)
                                    DimTxt(choice.note)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.panel)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hair))
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        DimTxt("Hesap Değişimi Yalnız Sizin Seçiminizle")
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: Accounts and cost

/// 9.1T
struct AccountsScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Daha", trailing: nil)
            HStack {
                ScreenTitle(text: "Hesaplar")
                Button { model.route.append(.accountAdd) } label: {
                    Txt("+ Ekle").frame(minHeight: 44).contentShape(Rectangle())
                }
                .padding(.trailing, 16)
            }
            Loaded(call: PhoneCall("accounts"), type: [PhoneAccount].self) { accounts, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(accounts) { account in
                            Card {
                                Txt(account.tool.title, bold: true)
                                DimTxt("\(account.name) · \(account.sessions) Oturum")
                                if account.isAPIKey {
                                    DimTxt("Abonelik Limiti Yok · Kullanıma Göre")
                                } else if account.tool == .antigravity {
                                    DimTxt("Limit Bilinmiyor")
                                } else if account.limit == nil {
                                    DimTxt("Henüz Bilinmiyor. İlk yanıttan sonra görünür.")
                                } else {
                                    LimitLines(limit: account.limit)
                                }
                            }
                        }
                        DimTxt("Hesap ekleme bilgisayarda sağlayıcının ekranında tamamlanır.")
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct AccountAddScreen: View {
    @EnvironmentObject var model: PhoneModel
    @State private var tool = ToolKind.claude
    @State private var name = ""
    @State private var started = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(back: "Hesaplar")
            VStack(alignment: .leading, spacing: 12) {
                Txt("Hesap Ekle", bold: true)
                Choice(options: [(ToolKind.claude, "Claude Code"), (ToolKind.codex, "Codex")], value: $tool)
                InputField(placeholder: "Bu Hesabın Adı: İş, Kişisel", text: $name)
                if started {
                    Txt("● Giriş Bekleniyor", bold: true)
                    DimTxt("Bilgisayarda yeni bir terminal açıldı. Resmi program kendi giriş ekranını gösterir, giriş orada tamamlanır.")
                } else {
                    DimTxt("Giriş sağlayıcının kendi ekranında tamamlanır. Enterm abonelik şifresi görmez.")
                    ActionButton("Girişi Başlat", style: .primary) {
                        Task {
                            if case .success = await model.call(PhoneCall("accountAdd", args: ["tool": tool.rawValue, "name": name]), as: PhoneNothing.self) { started = true }
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
        }
    }
}

/// 10.2T: only numbers the programs reported. What is not reported separately says so.
struct CostScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Daha")
            ScreenTitle(text: "Model Ve Maliyet")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let lines = PhoneCost.byModel(model.sessions)
                    if lines.isEmpty { DimTxt("Çalışan Ajan Yok.") }
                    ForEach(lines) { line in
                        HStack {
                            Txt(line.name)
                            Spacer()
                            DimTxt(PhoneCost.short(line.tokens))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Palette.surface1)
                        .cornerRadius(8)
                    }
                    Card {
                        HStack {
                            Txt("Danışman")
                            Spacer()
                            Txt("Ayrı Sayım Yok", color: Palette.text2, style: .subheadline)
                        }
                        DimTxt("Tüketim limit yüzdesine dahildir, ayrı okunamıyor. Toplam gerçek kullanımdan düşük görünebilir.")
                    }
                    ForEach(model.sessions.filter { $0.tool != .terminal }) { info in
                        Card {
                            HStack {
                                Txt(model.title(info), bold: true).lineLimit(1)
                                Spacer()
                                DimTxt(info.contextTokens.map(PhoneCost.short) ?? "-")
                            }
                            if let name = info.model { DimTxt(name) }
                            if let cost = info.costUSD { DimTxt(String(format: "$%.2f Liste Fiyatı", cost)) }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// 13.4T
struct PowerScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Daha")
            ScreenTitle(text: "Güç Sınırı")
            Loaded(call: PhoneCall("power"), type: PhonePower.self) { power, reload in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        DimTxt("Bilgisayardaki Enterm'e uygulanır.")
                        Card {
                            DimTxt("Düşük Güçlü Bilgisayar")
                            Choice(options: [(false, "Kapalı"), (true, "Açık")], value: Binding(
                                get: { power.settings.lowPower },
                                set: { value in set(["lowPower": value ? "1" : "0"], reload) }))
                        }
                        Card {
                            DimTxt("Bilgisayarın Gücünün En Çok Şu Kadarını Kullan")
                            Choice(options: [(25, "%25"), (50, "%50"), (75, "%75"), (100, "Sınırsız")], value: Binding(
                                get: { power.settings.cpuLimit },
                                set: { value in set(["cpuLimit": String(value)], reload) }))
                            DimTxt("Üst hedeftir, kesin ölçüm değildir. Yeni iş sıraya girer, düz terminallere dokunulmaz.")
                        }
                        Card {
                            DimTxt("Aynı Anda En Çok Şu Kadar Oturum Çalışsın: \(power.effectiveSessions)")
                            Choice(options: [(true, "Otomatik"), (false, "Elle")], value: Binding(
                                get: { power.settings.sessionsAutomatic },
                                set: { value in set(["automatic": value ? "1" : "0"], reload) }))
                        }
                        Card {
                            Txt("Şu Anki Kullanım", bold: true)
                            HStack { DimTxt("Enterm"); Spacer(); DimTxt(power.enterm) }
                            HStack { DimTxt("Claude Code Ve Codex"); Spacer(); DimTxt(power.agents) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    private func set(_ args: [String: String], _ reload: @escaping () -> Void) {
        Task {
            _ = await model.call(PhoneCall("powerSet", args: args), as: PhonePower.self)
            reload()
        }
    }
}

// MARK: New session

/// 3.2T
struct NewOptionsScreen: View {
    @EnvironmentObject var model: PhoneModel
    @State private var name = ""
    @State private var folder = ""
    @State private var tool = ToolKind.terminal
    @State private var account = ""
    @State private var template = PermissionTemplate.development
    @State private var modelName = ""
    @State private var effort = ""
    @State private var picking = false

    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Vazgeç", trailing: "Yeni Oturum")
            Loaded(call: PhoneCall("options"), type: PhoneOptions.self) { options, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        DimTxt("Oturum Adı")
                        InputField(placeholder: "İsteğe Bağlı", text: $name)
                        DimTxt("Çalışma Alanı")
                        InputField(placeholder: "~/projeler/magaza", text: $folder)
                        ActionButton("Klasör Seç", style: .plain) { picking = true }
                        ForEach(options.folders, id: \.self) { path in
                            ActionButton(path, style: .outline) { folder = path }
                        }
                        DimTxt("Araç")
                        Choice(options: ToolKind.allCases.map { kind in
                            let note = options.notes[kind.rawValue] ?? ""
                            return (kind, note.isEmpty ? kind.title : "\(kind.title) · \(note)")
                        }, value: Binding(get: { tool }, set: { tool = $0; account = "" }))
                        if tool != .terminal {
                            DimTxt("Hesap")
                            Choice(options: options.accounts.filter { $0.tool == tool }.map { ($0.id, title($0)) }, value: Binding(
                                get: { account.isEmpty ? "system-\(tool.rawValue)" : account },
                                set: { account = $0 }))
                            DimTxt("Model Davranışı")
                            Choice(options: [("", "Otomatik"), ("haiku", "Haiku"), ("sonnet", "Sonnet"), ("opus", "Opus")], value: $modelName)
                            DimTxt("Efor")
                            Choice(options: [("", "Otomatik"), ("medium", "Orta"), ("high", "Yüksek")], value: $effort)
                            DimTxt("Yetki Şablonu")
                            Choice(options: PermissionTemplate.allCases.map { ($0, $0.title) }, value: $template)
                        }
                        DimTxt("Oturum bilgisayarda başlar, telefon bağlanır.")
                        ActionButton("Başlat", style: .primary) {
                            Task {
                                await model.start(tool: tool, name: name, folder: folder, account: account,
                                                  template: tool == .terminal ? "" : template.rawValue, model: modelName, effort: effort)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $picking) {
            FilePicker(start: folder.isEmpty ? "~" : folder, foldersOnly: true) { folder = $0 }.environmentObject(model)
        }
#if DEBUG
        .onAppear { if TestForm.values == "pick" { picking = true } }
#endif
    }
    private func title(_ item: PhoneAccount) -> String {
        if let window = item.limit?.fiveHour { return "\(item.name) · %\(Int(window.usedPercent)) Dolu" }
        return item.name
    }
}

/// 1.4T when the program was chosen rather than typed.
struct InstallScreen: View {
    @EnvironmentObject var model: PhoneModel
    let tool: ToolKind
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(back: "Vazgeç")
            VStack(alignment: .leading, spacing: 12) {
                Txt("\(tool.title) Bilgisayarda Kurulu Değil", bold: true)
                CommandText(text: ToolPresence.installCommand(tool) ?? "")
                DimTxt("Siz onaylamadan çalışmaz, önce doğrulama ister. Onaylarsanız bilgisayarda yeni terminalde görünür şekilde çalışır.")
                ActionButton("Bilgisayarda Çalıştır", style: .primary) {
                    Task {
                        if await model.install(tool) { model.route = [] }
                    }
                }
                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: Team

/// Kept while the three steps of building a team go on.
@MainActor
final class TeamDraft: ObservableObject {
    static let shared = TeamDraft()
    @Published var brief = ""
    @Published var folder = ""
    @Published var members: [TeamMember] = []
}

/// 14.1T
struct TeamStartScreen: View {
    @EnvironmentObject var model: PhoneModel
    @ObservedObject var draft = TeamDraft.shared
    private let templates = [("software", "Yazılım", "Yönetici, Geliştirici, Test"), ("marketing", "Pazarlama", "Yönetici, Strateji, Metin"),
                             ("company", "Tam Şirket", "Yazılım, Tasarım, İçerik"), ("empty", "Boş", "Yalnız Yönetici")]
    @State private var key = "software"
    @State private var picking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(back: "Daha", trailing: "Adım 1 / 3")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Txt("Ekibini Kur", bold: true)
                    DimTxt("Projeyi Bir Cümleyle Anlatın")
                    InputField(placeholder: "Kuponlu e-ticaret sitesine iade akışı", text: $draft.brief)
                    DimTxt("Ya Da Şablon Seçin")
                    ForEach(templates, id: \.0) { item in
                        Button { key = item.0 } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Txt(item.1, bold: true)
                                DimTxt(item.2)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(key == item.0 ? Palette.fillSelected : Palette.fill)
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    DimTxt("Klasör")
                    InputField(placeholder: "~/projeler/magaza", text: $draft.folder)
                    ActionButton("Klasör Seç", style: .plain) { picking = true }
                    ActionButton("Kadro Öner", style: .primary) {
                        draft.members = Team.template(key)
                        model.route.append(.teamRoster)
                    }
                    .disabled(draft.folder.isEmpty)
                    if draft.folder.isEmpty { DimTxt("Önce klasör yazın.") }
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $picking) {
            FilePicker(start: draft.folder.isEmpty ? "~" : draft.folder, foldersOnly: true) { draft.folder = $0 }.environmentObject(model)
        }
    }
}

/// 14.2T
struct TeamRosterScreen: View {
    @EnvironmentObject var model: PhoneModel
    @ObservedObject var draft = TeamDraft.shared
    @State private var open: String?
    @State private var problem: String?
    @State private var picking: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(back: "Geri", trailing: "Adım 2 / 3")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Txt("Kadro Önerisi", bold: true)
                    ForEach($draft.members) { $member in
                        Button { open = open == member.id ? nil : member.id } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Txt("\(member.name) · \(member.role)", bold: true)
                                DimTxt("\(member.tool.title) · \(member.model) · Kart: \(member.template.title)")
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface1)
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if open == member.id {
                            InputField(placeholder: "Ad", text: $member.name)
                            InputField(placeholder: "Rol", text: $member.role)
                            Choice(options: [(ToolKind.claude, "Claude"), (ToolKind.codex, "Codex")], value: $member.tool)
                            InputField(placeholder: "Model", text: $member.model)
                            Choice(options: PermissionTemplate.allCases.map { ($0, $0.title) }, value: $member.template)
                            InputField(placeholder: "Kaynak Dosyalar", text: $member.sources)
                            ActionButton("Kaynak Dosya Seç", style: .plain) { picking = member.id }
                            ActionButton("Üyeyi Çıkar") { draft.members.removeAll { $0.id == member.id } }
                        }
                    }
                    ActionButton("Üye Ekle") { draft.members.append(TeamMember(name: "Yeni Üye", role: "Geliştirici")) }
                    DimTxt("Satıra dokununca rol, araç, model, yetki kartı ve kaynak dosyalar açılır.")
                    Txt("Onayınız Olmadan Hiçbir Ajan Başlamaz", color: Palette.need)
                    if let problem { Txt(problem, color: Palette.err) }
                    ActionButton("Onayla Ve Ekibi Kur", style: .primary) { build() }
                }
                .padding(16)
            }
        }
        .sheet(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } })) {
            FilePicker(start: draft.folder.isEmpty ? "~" : draft.folder, foldersOnly: false) { path in
                guard let index = draft.members.firstIndex(where: { $0.id == picking }) else { return }
                let current = draft.members[index].sources
                draft.members[index].sources = current.isEmpty ? path : current + ", " + path
            }
            .environmentObject(model)
        }
    }
    private func build() {
        guard let data = try? JSONEncoder().encode(draft.members) else { return }
        let args = ["brief": draft.brief, "folder": draft.folder, "members": String(decoding: data, as: UTF8.self)]
        Task {
            switch await model.confirmedCall("Ekibi başlatmak için doğrulayın.", PhoneCall("teamBuild", args: args), as: PhoneNothing.self) {
            case .success:
                model.route = [.teamDecisions]
            case .failure(let error):
                problem = error.message
            }
        }
    }
}

/// 14.6T: what waits for the person, and the reports behind it.
struct TeamDecisionsScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Daha", trailing: "Adım 3 / 3")
            Loaded(call: PhoneCall("team"), type: Team.self) { team, reload in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if team.members.isEmpty {
                            DimTxt("Henüz Ekip Yok.")
                            NavRow("Ekibini Kur") { model.route.append(.teamStart) }
                        } else {
                            Txt("\(team.name) Ekibi", bold: true)
                            let pending = model.waitingApprovals
                            Txt("Bekleyen Kararlar \(pending.count)", bold: true)
                            ForEach(pending) { info in
                                if let approval = info.pendingApproval { ApprovalCard(info: info, approval: approval) }
                            }
                            ForEach(team.members) { member in
                                let info = model.sessions.first { $0.id == member.sessionID }
                                if let info, let used = info.limit?.fiveHour?.usedPercent, used >= 90 {
                                    Card {
                                        Txt("Hesap: \(member.name)", bold: true)
                                        DimTxt("Hesap %\(Int(used)) dolu, iş bitmeyebilir.")
                                        ActionButton("Seçenekler") { model.route.append(.limit(info.number)) }
                                    }
                                }
                            }
                            Txt("Kadro", bold: true)
                            ForEach(team.members) { member in
                                let info = model.sessions.first { $0.id == member.sessionID }
                                HStack {
                                    Txt(member.name)
                                    DimTxt(member.role)
                                    Spacer()
                                    if let info { StatusText(info: info) } else { DimTxt("Çalışmıyor") }
                                }
                            }
                            Txt("Raporlar \(team.reports.count)", bold: true)
                            if team.reports.isEmpty { DimTxt("Henüz Rapor Gelmedi.") }
                            ForEach(team.reports) { report in
                                NavRow("\(report.author): \(report.changed)") { model.route.append(.report(report.id)) }
                            }
                            DimTxt("Ajan mesajı onay sayılmaz.")
                            ActionButton("Yenile", style: .plain, action: reload)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

/// 14.5T
struct ReportScreen: View {
    @EnvironmentObject var model: PhoneModel
    let id: String
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Kararlar", trailing: "Ajan Raporu")
            Loaded(call: PhoneCall("team"), type: Team.self) { team, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let report = team.reports.first(where: { $0.id == id }) {
                            Txt(report.author, bold: true)
                            section("Ne Değişti", report.changed)
                            section("Ne Denendi", report.tried)
                            section("Ne Denenmedi", report.notTried)
                            section("Ne Bekliyor", report.waiting)
                            DimTxt("Bu kart ajan mesajıdır, onay sayılmaz.")
                        } else {
                            DimTxt("Rapor Bulunamadı.")
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
    private func section(_ title: String, _ text: String) -> some View {
        Card {
            Txt(title, bold: true)
            Txt(text)
        }
    }
}


// MARK: Waiting and limits

/// Browses the Mac's folders, because a phone has no other way to know their names.
struct FilePicker: View {
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    let start: String
    let foldersOnly: Bool
    let onPick: (String) -> Void
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: { BackLabel(title: "Vazgeç") }.buttonStyle(.plain)
                Spacer()
                if !path.isEmpty, path != "/" {
                    Button { path = (path as NSString).deletingLastPathComponent } label: { Txt("Üst Klasör").frame(minHeight: 44).contentShape(Rectangle()) }
                }
            }
            .padding(.horizontal, 12)
            Loaded(call: PhoneCall("files", args: ["path": path.isEmpty ? start : path]), type: PhoneFiles.self) { files, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Txt(files.display, bold: true)
                        if foldersOnly {
                            ActionButton("Bu Klasörü Seç", style: .primary) {
                                onPick(files.display)
                                dismiss()
                            }
                        }
                        ForEach(files.items.filter { !foldersOnly || $0.isDirectory }) { item in
                            NavRow(item.isDirectory ? "\(item.name)/" : item.name) {
                                let full = (files.path as NSString).appendingPathComponent(item.name)
                                if item.isDirectory {
                                    path = full
                                } else {
                                    onPick((files.display as NSString).appendingPathComponent(item.name))
                                    dismiss()
                                }
                            }
                        }
                        if files.items.isEmpty { DimTxt("Bu Klasör Boş.") }
                    }
                    .padding(16)
                }
            }
            .id(path)
        }
        .background(Palette.bg)
    }
}

/// The decision stays in reach, however long the command is: the box scrolls inside itself.
struct ApprovalDetailScreen: View {
    @EnvironmentObject var model: PhoneModel
    let id: String
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Onaylar", asksApproval: true)
            if let info = model.sessions.first(where: { $0.pendingApproval?.id == id }), let approval = info.pendingApproval {
                VStack(alignment: .leading, spacing: 8) {
                    Txt("\(model.title(info)) İzin İstiyor", bold: true)
                    DimTxt("Hangi Komut")
                    ScrollView {
                        Text(approval.summary)
                            .font(.mono)
                            .foregroundColor(Palette.terminalText)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Palette.terminal)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hair2))
                    DimTxt("Yetki: \(approval.category.title)")
                    NavRow("Yetki Kartını Aç") { model.route.append(.card(info.number)) }
                }
                .padding(16)
                .safeAreaInset(edge: .bottom) {
                    ButtonPair {
                        ActionButton("Reddet") { model.decide(id: id, decision: "deny") }
                    } main: {
                        ActionButton("İzin Ver", style: .primary) { Approval.allow(id: id) }
                    }
                    .padding(12)
                    .background(Palette.surface1)
                }
            } else {
                DimTxt("Bu istek artık bekliyor değil.").padding(16)
                Spacer()
            }
        }
    }
}

/// 4.7T
struct QueuedScreen: View {
    @EnvironmentObject var model: PhoneModel
    let id: String
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Oturumlar", trailing: "◷ Sırada")
            VStack(alignment: .leading, spacing: 12) {
                if let item = model.attention.queue.first(where: { $0.id == id }) {
                    Txt(item.name, bold: true)
                    Txt("Yer Açılınca Kendiliğinden Başlar", bold: true)
                    DimTxt(item.reason)
                    DimTxt("Çalışan iş durmadı. Bu oturum henüz başlamadı, token harcamıyor.")
                    if let program = item.tool.command { CommandText(text: program) }
                    ActionButton("Yine De Başlat", style: .primary) {
                        Task {
                            let result = await model.confirmedCall("\(item.tool.title) başlatmak için doğrulayın.", PhoneCall("queueStart", args: ["id": id]), as: PhoneNothing.self)
                            if case .success = result, !model.route.isEmpty { model.route.removeLast() }
                        }
                    }
                    NavRow("Güç Sınırı") { model.route.append(.power) }
                } else {
                    DimTxt("Bu oturum artık sırada değil.")
                }
                Spacer()
            }
            .padding(16)
        }
    }
}

/// 9.5T
struct LimitOpenedScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Onaylar", trailing: "✓ Limit Açıldı")
            VStack(alignment: .leading, spacing: 12) {
                if let account = model.attention.limitReturnAccount {
                    Txt("Başladığınız hesabın limiti açıldı, dönülsün mü?", bold: true)
                    DimTxt("Dönülecek: \(account). Dönüş, hesap değişimi gibi ilk mesajda konuşmayı baştan okur.")
                    ActionButton("\(account) Hesabına Dön", style: .primary) {
                        Task {
                            let result = await model.confirmedCall("Hesap değişimi için doğrulayın.", PhoneCall("limitReturn", args: ["go": "1"]), as: PhoneNothing.self)
                            if case .success = result { model.route = [] }
                        }
                    }
                    ActionButton("Burada Kalsın") {
                        Task {
                            _ = await model.call(PhoneCall("limitReturn", args: ["go": "0"]), as: PhoneNothing.self)
                            model.route = []
                        }
                    }
                } else {
                    DimTxt("Bekleyen Bir Şey Yok.")
                }
                Spacer()
            }
            .padding(16)
        }
    }
}

/// 9.6T
struct ResumeFailedScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Onaylar", trailing: "■ Durdu")
            Loaded(call: PhoneCall("resumeChoices", number: number), type: [PhoneChoice].self) { choices, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Txt(model.session(number).map { model.title($0) } ?? "Oturum", bold: true)
                        DimTxt("Konuşma bu hesapta açılmadı. İş kaybolmadı.")
                        ForEach(choices) { choice in
                            Button {
                                Task {
                                    let result = await model.confirmedCall("Devam etmek için doğrulayın.", PhoneCall("resumeRun", number: number, args: ["index": String(choice.id)]), as: PhoneNothing.self)
                                    if case .success = result { model.route = [] }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Txt(choice.title, bold: true)
                                    DimTxt(choice.note)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.panel)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hair))
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

/// 9.7T
struct CodexLimitScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: UInt32
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Onaylar", trailing: "■ Kontrol Edin")
            VStack(alignment: .leading, spacing: 12) {
                Txt(model.session(number).map { "\(model.title($0)) · Codex" } ?? "Codex", bold: true)
                Txt("Limit Dolmuş Olabilir, Kontrol Edin", bold: true)
                DimTxt("Son tur başarısız oldu, kesin bilgi gelmedi.")
                LimitLines(limit: model.session(number)?.limit)
                ActionButton("Terminale Bak") {
                    clear()
                    model.route = []
                    model.openSession = number
                }
                ActionButton("Limit Doldu, Seçenekler") {
                    clear()
                    model.route.append(.limit(number))
                }
                ActionButton("Sorun Yok", style: .plain) {
                    clear()
                    model.route = []
                }
                Spacer()
            }
            .padding(16)
        }
    }
    private func clear() {
        Task { _ = await model.call(PhoneCall("attentionClear", number: number), as: PhoneNothing.self) }
    }
}
