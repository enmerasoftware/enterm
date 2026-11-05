import AppKit
import EntermCore
import SwiftUI

/// The same session, read as a conversation. It reads the program's own transcript and types into its terminal,
/// so nothing is sent twice and the terminal stays the truth. It reads only while it is on screen.
final class ChatFeed: ObservableObject {
    @Published var items: [ChatItem] = []
    @Published var unavailable = false
    private var source: DispatchSourceFileSystemObject?
    private var path: String?
    private var offset: UInt64 = 0
    private var parser = ChatParser()
    private let queue = DispatchQueue(label: "enterm.chat", qos: .utility)

    func watch(path: String?) {
        guard path != self.path else { return }
        stop()
        self.path = path
        guard let path, FileManager.default.fileExists(atPath: path) else {
            unavailable = true
            return
        }
        unavailable = false
        offset = 0
        parser = ChatParser()
        items = []
        readMore(path)
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend], queue: queue)
        source.setEventHandler { [weak self] in self?.readMore(path) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        path = nil
    }

    deinit { source?.cancel() }

    private func readMore(_ path: String) {
        queue.async { [weak self] in
            guard let self, let handle = FileHandle(forReadingAtPath: path) else { return }
            defer { try? handle.close() }
            // A long conversation starts from its last part: the screen shows the end anyway.
            let size = (try? handle.seekToEnd()) ?? 0
            if self.offset == 0, size > 2_000_000 { self.offset = size - 2_000_000 }
            try? handle.seek(toOffset: self.offset)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
            guard let last = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
            let complete = data[data.startIndex...last]
            self.offset += UInt64(complete.count)
            self.parser.feed(String(decoding: complete, as: UTF8.self))
            let items = self.parser.items
            DispatchQueue.main.async { self.items = items }
        }
    }
}

struct ChatView: View {
    let number: UInt32
    @ObservedObject var model = AppModel.shared
    @StateObject private var feed = ChatFeed()
    @State private var draft = ""
    @FocusState private var typing: Bool

    private var info: SessionInfo? { model.sessions.first { $0.number == number } }

    var body: some View {
        let palette = Theme.palette
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if feed.items.isEmpty {
                            Dim(feed.unavailable ? "Konuşma dosyası henüz yok. İlk yanıttan sonra burada görünür." : "Konuşma okunuyor.")
                                .padding(.top, 24)
                        }
                        ForEach(feed.items) { item in
                            ChatRow(item: item)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .onChange(of: feed.items.count) { _ in reader.scrollTo("end", anchor: .bottom) }
                .onAppear { reader.scrollTo("end", anchor: .bottom) }
            }
            if let request = info?.pendingApproval {
                VStack(alignment: .leading, spacing: 8) {
                    T("Şu izni istiyor:", color: palette.need, style: .secondary, weight: .semibold)
                    Mono(request.summary).lineLimit(4).textSelection(.enabled)
                    HStack {
                        Btn("İzin Ver", kind: .primary) { Approvals.decide(id: request.id, decision: "allow") }
                        Btn("Reddet", kind: .outline) { Approvals.decide(id: request.id, decision: "deny") }
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color(palette.need).opacity(0.08))
                .overlay(alignment: .top) { Rectangle().fill(Color(palette.need).opacity(0.5)).frame(height: 1) }
            }
            // The program asked on its own screen: its first choice is yes, Esc is no.
            if let info, info.status == .needsApproval, info.pendingApproval == nil {
                VStack(alignment: .leading, spacing: 8) {
                    T("Şu izni istiyor:", color: palette.need, style: .secondary, weight: .semibold)
                    if let last = info.lastActivity { Mono(last).lineLimit(4).textSelection(.enabled) }
                    HStack {
                        Btn("İzin Ver", kind: .primary) { model.hosts[number]?.type("\r") }
                        Btn("Reddet", kind: .outline) { model.hosts[number]?.type("\u{1b}") }
                        Spacer()
                        Btn("Terminali Aç", kind: .plain) { model.toggleChat(number) }
                    }
                }
                .padding(12)
                .background(Color(palette.need).opacity(0.08))
                .overlay(alignment: .top) { Rectangle().fill(Color(palette.need).opacity(0.5)).frame(height: 1) }
            }
            HStack(spacing: 10) {
                Text("❯").font(Theme.swiftFont(size: 14)).foregroundColor(Color(palette.need))
                TextField("", text: $draft, prompt: Text("Yanıt yazın").foregroundColor(Color(palette.text3)), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .focused($typing)
                    .onSubmit(send)
                Button(action: send) {
                    Text("⏎").font(.system(size: 14)).foregroundColor(Color(palette.need)).frame(width: 28, height: 26)
                        .background(Color(palette.surface2)).cornerRadius(Theme.cornerControl)
                }
                .buttonStyle(.plain)
                .disabled(draft.isEmpty)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(palette.surface1))
            .overlay(alignment: .top) { Line() }
        }
        .background(Color(palette.surface0))
        .cornerRadius(Theme.cornerCard, corners: [.topRight, .bottomLeft, .bottomRight])
        .onAppear {
            feed.watch(path: info?.transcriptPath)
            typing = true
        }
        .onChange(of: info?.transcriptPath) { feed.watch(path: $0) }
        .onDisappear { feed.stop() }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // Text and Enter go separately, the way a person types: a program may treat a burst as a paste.
        model.hosts[number]?.type(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { model.hosts[number]?.type("\r") }
    }
}

/// What a program asks, at the foot of its own box. Enter and Y do nothing here: only a click answers, so typing elsewhere never can.
struct ApprovalBar: View {
    let request: ApprovalRequest
    let number: UInt32
    var body: some View {
        let palette = Theme.palette
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Symbol("diamond.fill", color: palette.need, size: 10)
                T(request.category.title, color: palette.need, style: .secondary, weight: .semibold)
                Spacer(minLength: 8)
                Btn("Ayrıntı", kind: .plain) { AppModel.shared.overlay = .approval(request.id) }
                Btn("Reddet") { Approvals.decide(id: request.id, decision: "deny") }
                Btn("İzin Ver", kind: .primary) { Approvals.decide(id: request.id, decision: "allow") }
            }
            Mono(request.summary).lineLimit(2).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(palette.surface2))
        .overlay(alignment: .top) { Rectangle().fill(Color(palette.need).opacity(0.6)).frame(height: 1) }
    }
}

private struct ChatRow: View {
    let item: ChatItem
    var body: some View {
        let palette = Theme.palette
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(item.text)
                    .font(.system(size: 14))
                    .foregroundColor(Color(palette.text1))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(palette.surface2))
                    .cornerRadius(10)
            }
        case .assistant:
            ChatMarkdown(text: item.text)
        case .tool:
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Color(palette.g1)).frame(width: 6, height: 6).padding(.top, 5)
                Text(item.text)
                    .font(Theme.swiftFont(size: 12))
                    .foregroundColor(Color(palette.text3))
                    .lineLimit(2)
            }
        }
    }
}

/// Headings, lists, code blocks and inline marks. Enough to read an answer, without a web view.
private struct ChatMarkdown: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(_ block: MarkdownBlock) -> some View {
        let palette = Theme.palette
        switch block {
        case .code(let code):
            Text(code)
                .font(Theme.swiftFont(size: 12))
                .foregroundColor(Color(palette.terminalText))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(palette.terminal))
                .cornerRadius(Theme.cornerControl)
        case .heading(let line):
            inline(line).font(.system(size: 15, weight: .semibold)).foregroundColor(Color(palette.text1))
        case .paragraph(let line):
            inline(line).font(.system(size: 14)).foregroundColor(Color(palette.text1)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case .bullet(let line):
            HStack(alignment: .top, spacing: 8) {
                Text("·").font(.system(size: 14, weight: .bold)).foregroundColor(Color(palette.text2))
                inline(line).font(.system(size: 14)).foregroundColor(Color(palette.text1)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inline(_ line: String) -> Text {
        if let attributed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(line)
    }
}

extension AppModel {
    func toggleChat(_ number: UInt32) {
        if chatSessions.contains(number) { chatSessions.remove(number) } else { chatSessions.insert(number) }
        onLayoutChange?()
        if !chatSessions.contains(number) { refocusTerminalLater() }
    }
}
