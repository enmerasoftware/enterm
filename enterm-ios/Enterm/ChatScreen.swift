import EntermCore
import SwiftUI

/// A Claude Code or Codex session read as a conversation. The Mac sends its transcript a piece at a time,
/// only while this screen is open; what is typed here goes into the same terminal, so the Mac stays the truth.
@MainActor
final class PhoneChatFeed: ObservableObject {
    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var missing = false
    private var parser = ChatParser()
    private var offset: Int64?
    private var task: Task<Void, Never>?

    func start(_ number: UInt32, model: PhoneModel) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pull(number, model: model)
                // A conversation changes in bursts; a second and a half keeps up without keeping the link busy.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func pull(_ number: UInt32, model: PhoneModel) async {
        if model.isDemo {
            if items.isEmpty { items = Self.demo }
            return
        }
        guard let piece = await model.chat(number, from: offset) else {
            if offset == nil { missing = true }
            return
        }
        missing = false
        if piece.reset {
            parser = ChatParser()
            items = []
        }
        offset = piece.offset
        guard !piece.text.isEmpty else { return }
        parser.feed(piece.text)
        items = parser.items
    }

    private static let demo = [
        ChatItem(id: 0, role: .user, text: "Tek kutulu projelerde çerçeveyi kaldır."),
        ChatItem(id: 1, role: .tool, text: "Read Workspace.swift"),
        ChatItem(id: 2, role: .tool, text: "Edit CanvasView.swift"),
        ChatItem(id: 3, role: .assistant, text: "Çerçeve artık yalnız birden çok kutu olduğunda çiziliyor. **Testler geçti.**"),
    ]
}

struct ChatPane: View {
    @EnvironmentObject var model: PhoneModel
    let info: SessionInfo
    @StateObject private var feed = PhoneChatFeed()
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if feed.items.isEmpty {
                            DimTxt(feed.missing ? "Konuşma dosyası henüz yok. İlk yanıttan sonra burada görünür." : "Konuşma okunuyor.")
                                .padding(.top, 24)
                        }
                        ForEach(feed.items) { item in
                            PhoneChatRow(item: item)
                        }
                        if info.status == .running {
                            HStack(spacing: 8) {
                                Circle().fill(Palette.add).frame(width: 6, height: 6)
                                DimTxt(info.lastActivity ?? "Çalışıyor")
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: feed.items.count) { _ in withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo("end", anchor: .bottom) } }
                .onAppear { reader.scrollTo("end", anchor: .bottom) }
            }
            inputBar
        }
        .background(Palette.bg)
        .onAppear { feed.start(info.number, model: model) }
        .onDisappear { feed.stop() }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Yanıt yazın", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.field)
                .cornerRadius(10)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundColor(Palette.btnfg)
                    .frame(width: 40, height: 40)
                    .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Palette.fillSelected : Palette.btn)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Gönder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.surface1)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // Text and Enter go separately, the way a person types: a program may take a burst for a paste.
        model.input(info.number, Data(text.utf8))
        let number = info.number
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [model] in model.input(number, Data("\r".utf8)) }
    }
}

private struct PhoneChatRow: View {
    let item: ChatItem
    var body: some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(item.text)
                    .font(.body)
                    .foregroundColor(Palette.text1)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Palette.surface2)
                    .cornerRadius(14)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(MarkdownBlock.parse(item.text).enumerated()), id: \.offset) { _, block in
                    PhoneMarkdownBlock(block: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Palette.add).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(item.text)
                    .font(Font.mono)
                    .foregroundColor(Palette.text3)
                    .lineLimit(2)
            }
        }
    }
}

private struct PhoneMarkdownBlock: View {
    let block: MarkdownBlock
    var body: some View {
        switch block {
        case .heading(let text):
            Text(inline(text)).font(.headline).foregroundColor(Palette.text1)
        case .paragraph(let text):
            Text(inline(text)).font(.body).foregroundColor(Palette.text1).textSelection(.enabled)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundColor(Palette.text2)
                Text(inline(text)).font(.body).foregroundColor(Palette.text1)
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(Font.mono).foregroundColor(Palette.text1).padding(10)
            }
            .background(Palette.field)
            .cornerRadius(8)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
