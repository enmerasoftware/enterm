import EntermCore
import SwiftUI

// The phone's shell: one place to start work, a drawer for everything open, decisions rising from below.

/// A round control. Everything floating at the top of a screen is one of these.
struct CircleControl: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundColor(Palette.text1)
                .frame(width: 44, height: 44)
                .background(Palette.surface1)
                .overlay(Circle().stroke(Palette.hair2))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The title of a top-level screen, with the way to the drawer.
struct ShellTitle: View {
    @EnvironmentObject var model: PhoneModel
    let text: String
    var body: some View {
        HStack {
            CircleControl(symbol: "line.3.horizontal", label: "Oturumlar") { model.setDrawer(true) }
            Spacer()
            Txt(text, bold: true)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

/// A soft pulse of light around what is alive. Still when the person asked for less motion.
struct Pulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let color: Color
    var radius: CGFloat = 16
    @State private var high = false
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(reduce ? 0.4 : (high ? 0.75 : 0.25)), radius: reduce ? radius / 2 : (high ? radius : radius / 3))
            .onAppear {
                guard !reduce else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { high = true }
            }
    }
}

extension View {
    func pulse(_ color: Color, radius: CGFloat = 16) -> some View { modifier(Pulse(color: color, radius: radius)) }
}

/// The line under a working session's title: light running along it.
struct ScanLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var moved = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.hair)
                if !reduce {
                    Rectangle().fill(Palette.add)
                        .frame(width: 140)
                        .shadow(color: Palette.add, radius: 6)
                        .offset(x: moved ? geometry.size.width : -140)
                }
            }
        }
        .frame(height: 2)
        .clipped()
        .onAppear { withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) { moved = true } }
    }
}

/// What the next session will be. The sheet sets it, the line on the home screen uses it.
@MainActor final class StartDraft: ObservableObject {
    static let shared = StartDraft()
    @Published var tool = ToolKind.claude
    @Published var folder = ""
    @Published var account = ""
    @Published var template = PermissionTemplate.development
    @Published var modelName = ""
    @Published var effort = ""
}

// MARK: Home

struct HomeScreen: View {
    @EnvironmentObject var model: PhoneModel
    @ObservedObject private var draft = StartDraft.shared
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var text = ""
    @State private var adding = false
    @State private var breathing = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 8) {
            ConnectionBanner()
            HStack {
                CircleControl(symbol: "line.3.horizontal", label: "Oturumlar") { model.setDrawer(true) }
                Spacer()
                macPill
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            OfflineCard()
            if !typing { hero }
            Spacer(minLength: 0)
            problems
            if let waiting = model.waitingApprovals.first {
                approvalStrip(waiting)
            }
            composer
        }
        .padding(.bottom, 8)
        .background(Palette.terminal.ignoresSafeArea())
        .sheet(isPresented: $adding) {
            AddSheet().environmentObject(model).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

    private var macPill: some View {
        let on = model.connection == .connected
        return Button { model.tab = 1 } label: {
            HStack(spacing: 8) {
                Circle().fill(on ? Palette.add : Palette.text3).frame(width: 8, height: 8).pulse(on ? Palette.add : .clear, radius: 8)
                Txt(model.peer?.name ?? "Bilgisayar", style: .subheadline, weight: .medium).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Palette.surface1)
            .overlay(Capsule().stroke(Palette.hair2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Palette.need.opacity(0.18)).frame(width: 72, height: 72).blur(radius: 12)
                    .scaleEffect(breathing ? 1.14 : 0.92)
                Text("❯_").font(.system(size: 34, weight: .semibold, design: .monospaced)).foregroundColor(Palette.need)
                    .shadow(color: Palette.need.opacity(0.7), radius: 10)
            }
            .onAppear {
                guard !reduce else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathing = true }
            }
            Txt("Ne Başlatalım?", style: .title, weight: .semibold)
            DimTxt(summary)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var summary: String {
        let running = model.sessions.filter { $0.status == .running }.count
        let waiting = model.waitingApprovals.count
        if running == 0 && waiting == 0 { return "Şu an çalışan iş yok" }
        var parts: [String] = []
        if running > 0 { parts.append("\(running) oturum çalışıyor") }
        if waiting > 0 { parts.append("\(waiting) oturum sizi bekliyor") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var problems: some View {
        if let problem = model.startProblem {
            Button { model.startProblem = nil } label: {
                Txt(problem, color: Palette.err, style: .subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
        if model.showQueuedNote {
            DimTxt("Sırada: Yer açılınca kendiliğinden başlar. Çalışan iş durmadı.")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }

    private func approvalStrip(_ info: SessionInfo) -> some View {
        Button { model.sheetApproval = info.number } label: {
            HStack(spacing: 10) {
                Image(systemName: "diamond.fill").font(.caption).foregroundColor(Palette.need)
                Txt("\(model.title(info)) izin istiyor", style: .subheadline, weight: .medium).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(Palette.need)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Palette.need.opacity(0.09))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.need.opacity(0.45)))
            .cornerRadius(16)
            .pulse(Palette.need, radius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typing {
                HStack(spacing: 6) {
                    Button { adding = true } label: {
                        Txt("\(draft.tool.title) · \(draft.template.title)", color: Palette.text2, style: .footnote, weight: .medium)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Palette.fill)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 12)
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { adding = true } label: {
                    Image(systemName: "plus").font(.title3).foregroundColor(Palette.text1)
                        .frame(width: 44, height: 44).background(Palette.fill).clipShape(Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Oturuma Ekle")
                TextField("", text: $text, prompt: Text("Bir iş yazın ya da konuşun").foregroundColor(Palette.text3), axis: .vertical)
                    .focused($typing)
                    .lineLimit(1...5)
                    .foregroundColor(Palette.text1)
                    .padding(.vertical, 11)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundColor(Palette.btnfg)
                        .frame(width: 44, height: 44).background(Palette.btn).clipShape(Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(canSend ? 1 : 0.4)
                .disabled(!canSend)
                .accessibilityLabel("Başlat")
            }
            .padding(8)
        }
        .background(Palette.surface1)
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Palette.hair2))
        .cornerRadius(30)
        .padding(.horizontal, 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: typing)
    }

    private var canSend: Bool { model.connection == .connected && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        text = ""
        typing = false
        let chosen = draft
        Task {
            await model.start(tool: chosen.tool, folder: chosen.folder, account: chosen.account, template: chosen.tool == .terminal ? "" : chosen.template.rawValue,
                              model: chosen.modelName, effort: chosen.effort, prompt: chosen.tool == .terminal ? "" : prompt)
        }
    }
}

// MARK: Drawer

struct SessionDrawer: View {
    @EnvironmentObject var model: PhoneModel
    private var needing: [SessionInfo] { model.sessions.filter { $0.pendingApproval != nil || $0.status == .limitReached || $0.status == .failed } }
    private var working: [SessionInfo] { model.sessions.filter { $0.status == .running && $0.pendingApproval == nil } }
    private var others: [SessionInfo] {
        let shown = Set((needing + working).map(\.number))
        return model.sessions.filter { !shown.contains($0.number) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("enterm").font(.system(.title2, design: .monospaced).weight(.semibold)).foregroundColor(Palette.text1)
                        Spacer()
                        CircleControl(symbol: "gearshape", label: "Ayarlar") { go { model.tab = 3 } }
                    }
                    .padding(.bottom, 8)
                    link("Tuval", icon: "square.grid.2x2") { go { model.tab = 1 } }
                    link("Onay Kutusu", icon: "checkmark.shield") { go { model.tab = 2 } }
                    link("Kullanım", icon: "chart.bar") { go { model.route.append(.usage) } }
                    section("Sizi Bekliyor", needing)
                    section("Çalışıyor", working)
                    section("Son Oturumlar", others)
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            Button { go { model.tab = 0; model.openSession = nil } } label: {
                Label("Yeni Oturum", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(Palette.btnfg)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 52)
                    .background(Palette.btn)
                    .clipShape(Capsule())
                    .pulse(Palette.need, radius: 12)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }

    private func go(_ action: () -> Void) {
        model.route = []
        action()
        model.setDrawer(false)
    }

    private func link(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundColor(Palette.text2)
                Txt(title)
                Spacer()
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func section(_ title: String, _ items: [SessionInfo]) -> some View {
        if !items.isEmpty {
            Txt(title, color: Palette.text3, style: .footnote).padding(.top, 14).padding(.bottom, 2)
            ForEach(items) { row($0) }
        }
    }

    private func row(_ info: SessionInfo) -> some View {
        Button {
            guard model.connection == .connected else { return }
            go {
                model.tab = 0
                if info.pendingApproval != nil { model.sheetApproval = info.number } else { model.openSession = info.number }
            }
        } label: {
            HStack(spacing: 12) {
                Txt(model.title(info), weight: info.pendingApproval != nil ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 8)
                mark(info)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func mark(_ info: SessionInfo) -> some View {
        if info.pendingApproval != nil {
            Txt("◆ Onay", color: Palette.need, style: .subheadline, weight: .medium).pulse(Palette.need, radius: 6)
        } else if info.status == .limitReached {
            Txt("■ Limit", color: Palette.limit, style: .subheadline, weight: .medium)
        } else if info.status == .failed {
            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundColor(Palette.err)
        } else if info.status == .running {
            ProgressView().tint(Palette.add).controlSize(.small)
        }
    }
}

// MARK: Approval

/// A decision rises from below, wherever the person is.
struct ApprovalSheet: View {
    @EnvironmentObject var model: PhoneModel
    let info: SessionInfo
    let approval: ApprovalRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Txt("◆ İzin İstiyor", color: Palette.need, style: .subheadline, weight: .semibold)
            Txt("\(model.title(info)) izin bekliyor", style: .title2, weight: .semibold)
            Text(approval.summary)
                .font(.mono)
                .foregroundColor(Palette.text1)
                .lineLimit(6)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.field)
                .cornerRadius(12)
            HStack {
                DimTxt("Yetki: \(approval.category.title)")
                Spacer()
                Button {
                    model.sheetApproval = nil
                    model.route.append(.approval(approval.id))
                } label: { Txt("Ayrıntı", style: .subheadline).frame(minHeight: 44) }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ActionButton("Reddet") {
                    model.decide(id: approval.id, decision: "deny")
                    model.sheetApproval = nil
                }
                ActionButton("İzin Ver", style: .primary) {
                    Approval.allow(id: approval.id)
                    model.sheetApproval = nil
                }
                .pulse(Palette.need)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.surface1)
    }
}

// MARK: Add

struct AddSheet: View {
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var draft = StartDraft.shared
    @State private var accounts: [PhoneAccount] = []
    @State private var picking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    CircleControl(symbol: "xmark", label: "Kapat") { dismiss() }
                    Spacer()
                    Txt("Oturuma Ekle", bold: true)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                group {
                    Button { picking = true } label: {
                        row("Klasör", value: draft.folder.isEmpty ? "Ana Klasör" : URL(fileURLWithPath: draft.folder).lastPathComponent)
                    }.buttonStyle(.plain)
                }
                group {
                    menu("Program", value: draft.tool.title, ToolKind.allCases.map { kind in (kind.title, { draft.tool = kind; draft.account = "" }) })
                    if draft.tool != .terminal {
                        divider
                        menu("Yetki", value: draft.template.title, PermissionTemplate.allCases.map { item in (item.title, { draft.template = item }) })
                    }
                }
                if draft.tool != .terminal {
                    group {
                        menu("Model", value: title(of: draft.modelName, in: Self.models), Self.models.map { item in (item.1, { draft.modelName = item.0 }) })
                        divider
                        menu("Efor", value: title(of: draft.effort, in: Self.efforts), Self.efforts.map { item in (item.1, { draft.effort = item.0 }) })
                        let mine = accounts.filter { $0.tool == draft.tool }
                        if mine.count > 1 {
                            divider
                            menu("Hesap", value: mine.first { $0.id == draft.account }?.name ?? mine[0].name, mine.map { item in (item.name, { draft.account = item.id }) })
                        }
                    }
                }
                DimTxt("Oturum bilgisayarda başlar, telefon bağlanır.").frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(Palette.surface1.ignoresSafeArea())
        .sheet(isPresented: $picking) {
            FilePicker(start: draft.folder.isEmpty ? "~" : draft.folder, foldersOnly: true) { draft.folder = $0 }.environmentObject(model)
        }
        .task {
            if case .success(let options) = await model.call(PhoneCall("options"), as: PhoneOptions.self) { accounts = options.accounts }
        }
    }

    private static let models = [("", "Otomatik"), ("haiku", "Haiku"), ("sonnet", "Sonnet"), ("opus", "Opus")]
    private static let efforts = [("", "Otomatik"), ("medium", "Orta"), ("high", "Yüksek")]
    private func title(of value: String, in list: [(String, String)]) -> String { list.first { $0.0 == value }?.1 ?? "Otomatik" }
    private var divider: some View { Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 16) }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content).background(Palette.raise).cornerRadius(18)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Txt(title)
            Spacer()
            Txt(value, color: Palette.text2).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(Palette.text3)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func menu(_ title: String, value: String, _ options: [(String, () -> Void)]) -> some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in Button(options[index].0, action: options[index].1) }
        } label: { row(title, value: value) }
    }
}

// MARK: Usage

struct UsageScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            RouteHeader(back: "Geri", trailing: "Kullanım")
            Loaded(call: PhoneCall("options"), type: PhoneOptions.self) { options, _ in
                let known = options.accounts.filter { $0.limit?.fiveHour != nil || $0.limit?.sevenDay != nil }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Txt(Self.sentence(known)).fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
                        ForEach(known) { account in
                            Txt(account.isAPIKey ? "\(account.tool.title) · \(account.name)" : account.tool.title, color: Palette.text3, style: .subheadline).padding(.top, 8)
                            if let window = account.limit?.fiveHour { card("5 Saatlik", window) }
                            if let window = account.limit?.sevenDay { card("Haftalık", window) }
                        }
                        if known.isEmpty { DimTxt("Henüz Bilinmiyor. İlk Yanıttan Sonra Görünür.") }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func card(_ title: String, _ window: LimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Txt(title)
                Spacer()
                DimTxt("%\(Int(window.usedPercent)) Dolu")
            }
            Bar(percent: window.usedPercent)
            if let date = window.resetsAt { DimTxt("Yenilenme: \(date.turkish(date: .abbreviated))") }
        }
        .padding(16)
        .background(Palette.surface1)
        .cornerRadius(18)
    }

    /// Whether the week lasts at the pace so far, in one sentence.
    static func sentence(_ accounts: [PhoneAccount], now: Date = Date()) -> String {
        let weeks = accounts.compactMap { $0.limit?.sevenDay }
        guard let busiest = weeks.max(by: { $0.usedPercent < $1.usedPercent }) else { return "Limit bilgisi ilk yanıttan sonra görünür." }
        guard let reset = busiest.resetsAt, reset > now else { return "Haftalık kullanım %\(Int(busiest.usedPercent))." }
        let week: TimeInterval = 7 * 86400
        let elapsed = max(week - reset.timeIntervalSince(now), 3600)
        let projected = busiest.usedPercent * week / elapsed
        let day = reset.formatted(Date.FormatStyle(locale: Locale(identifier: "tr_TR")).weekday(.wide))
        return projected < 100 ? "Yolunda. Bu hızla \(day) yenilenmesine kadar limitiniz yetecek." : "Bu hızla limit \(day) yenilenmesinden önce dolabilir."
    }
}

struct Bar: View {
    let percent: Double
    @State private var shown = false
    var body: some View {
        let color = percent >= 90 ? Palette.err : (percent >= 70 ? Palette.limit : Palette.add)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fillSelected)
                Capsule().fill(color).frame(width: geometry.size.width * (shown ? min(max(percent, 0), 100) / 100 : 0)).shadow(color: color, radius: 5)
            }
        }
        .frame(height: 8)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { shown = true } }
    }
}
