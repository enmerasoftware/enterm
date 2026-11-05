import AppKit
import EntermCore
import SwiftUI
import WebKit

/// One system web view, shared by the user and the agents. It exists only while someone uses it.
/// A session's logins are not kept and are not shared with agents.
final class BrowserCenter: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = BrowserCenter()
    @Published var address = "http://localhost:3000"
    @Published var failure: String?
    @Published var userHasControl = false
    @Published var steps: [String] = []
    @Published var agentName: String?
    @Published var current = ""
    @Published var isOpen = false
    private(set) var webView: WKWebView?
    private var parking: NSWindow?
    private var loadWaiters: [(Result<Void, Error>) -> Void] = []
    private var idleTimer: Timer?

    func ensure() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        isOpen = true
        park()
        return view
    }

    /// Keeps the view alive when the page is closed but an agent still uses it. The window is never shown.
    func park() {
        guard let webView, webView.window == nil || webView.superview == nil else { return }
        let window = parking ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        parking = window
        window.contentView = webView
    }

    /// Closing frees the web processes, so an unused browser costs nothing.
    func close() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        parking?.contentView = nil
        parking = nil
        isOpen = false
        userHasControl = false
        steps.removeAll()
        agentName = nil
        failure = nil
        idleTimer?.invalidate()
    }

    func closeIfUnused() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            guard AppModel.shared.page != .browser else { return }
            self?.close()
        }
    }

    func load(_ text: String, then: ((Result<Void, Error>) -> Void)? = nil) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = (value.hasPrefix("localhost") || value.hasPrefix("127.") ? "http://" : "https://") + value }
        guard let url = URL(string: value), url.scheme == "http" || url.scheme == "https" else {
            then?(.failure(BrowserError.message("Geçersiz adres.")))
            return
        }
        address = value
        failure = nil
        if let then { loadWaiters.append(then) }
        ensure().load(URLRequest(url: url))
    }

    enum BrowserError: Error { case message(String) }

    private func finishLoad(_ result: Result<Void, Error>) {
        let waiters = loadWaiters
        loadWaiters.removeAll()
        waiters.forEach { $0(result) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString { address = url }
        current = webView.title ?? ""
        finishLoad(.success(()))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure = "Bağlanamadı: \(address)"
        finishLoad(.failure(error))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failure = "Sayfa Yarıda Kaldı: \(address)"
        finishLoad(.failure(error))
    }

    // MARK: Agent commands

    func handle(message: WireMessage) {
        guard let id = message.id else { return }
        func reply(_ text: String?, _ error: String? = nil) {
            var answer = WireMessage(op: "browserReply")
            answer.id = id
            answer.text = text
            answer.error = error
            AppModel.shared.connection.send(answer)
        }
        guard let data = message.text?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String else {
            reply(nil, "Geçersiz komut.")
            return
        }
        let args = object["args"] as? [String: Any] ?? [:]
        if userHasControl {
            reply(nil, "Kullanıcı tarayıcıyı devraldı. Geri verene kadar bekleyin.")
            return
        }
        if let sessionID = message.event?.sessionID, let info = AppModel.shared.sessions.first(where: { $0.id == sessionID }) {
            agentName = AppModel.shared.title(for: info)
        }
        closeIfUnused()
        switch name {
        case "tarayici_ac":
            let address = args["adres"] as? String ?? ""
            note("\(address) açılıyor")
            load(address) { [weak self] result in
                switch result {
                case .success:
                    self?.note("\(self?.current ?? "") açıldı")
                    self?.readPage { reply($0, nil) }
                case .failure:
                    reply(nil, "Bağlanamadı: \(address)")
                }
            }
        case "tarayici_oku":
            note("Sayfa okundu")
            readPage { reply($0, nil) }
        case "tarayici_tikla":
            let target = args["hedef"] as? String ?? ""
            note("\"\(target)\" tıklanıyor")
            run(Self.clickScript(target)) { reply($0, $0 == "Bulunamadı" ? "Öğe bulunamadı: \(target)" : nil) }
        case "tarayici_yaz":
            let target = args["hedef"] as? String ?? ""
            note("\"\(target)\" alanına yazılıyor")
            run(Self.typeScript(target, args["metin"] as? String ?? "")) { reply($0, $0 == "Bulunamadı" ? "Alan bulunamadı: \(target)" : nil) }
        case "tarayici_goruntu":
            let view = ensure()
            view.takeSnapshot(with: nil) { image, _ in
                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    reply(nil, "Görüntü alınamadı.")
                    return
                }
                let dir = EntermPaths.support.appendingPathComponent("browser-shots", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970)).png")
                try? png.write(to: file)
                reply(file.path)
            }
        default:
            reply(nil, "Bilinmeyen komut.")
        }
    }

    private func note(_ text: String) {
        steps.insert(text, at: 0)
        if steps.count > 12 { steps.removeLast() }
    }

    private func readPage(_ done: @escaping (String) -> Void) {
        run("document.title + '\\n' + location.href + '\\n\\n' + (document.body ? document.body.innerText : '').slice(0, 8000)", done)
    }

    private func run(_ script: String, _ done: @escaping (String) -> Void) {
        ensure().evaluateJavaScript(script) { value, error in
            if let error { done("Hata: \(error.localizedDescription)"); return }
            done(value as? String ?? "\(value ?? "")")
        }
    }

    private static func jsString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }

    static func clickScript(_ target: String) -> String {
        """
        (function(){var t=\(jsString(target));var e=null;try{e=document.querySelector(t)}catch(x){}
        if(!e){var l=document.querySelectorAll('a,button,input[type=submit],input[type=button],[role=button],label,summary');
        for(var i=0;i<l.length;i++){var s=(l[i].innerText||l[i].value||'').trim();if(s===t){e=l[i];break}}
        if(!e)for(var j=0;j<l.length;j++){var c=(l[j].innerText||l[j].value||'');if(c.indexOf(t)>=0){e=l[j];break}}}
        if(!e)return 'Bulunamadı';e.click();return 'Tıklandı: '+(e.innerText||e.value||e.tagName).trim().slice(0,80)})()
        """
    }

    static func typeScript(_ target: String, _ text: String) -> String {
        """
        (function(){var t=\(jsString(target));var v=\(jsString(text));var e=null;try{e=document.querySelector(t)}catch(x){}
        if(!e){var l=document.querySelectorAll('input,textarea');for(var i=0;i<l.length;i++){if(l[i].name===t||l[i].placeholder===t||l[i].id===t||l[i].getAttribute('aria-label')===t){e=l[i];break}}}
        if(!e)return 'Bulunamadı';var p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
        var d=Object.getOwnPropertyDescriptor(p,'value');if(d&&d.set)d.set.call(e,v);else e.value=v;
        e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return 'Yazıldı'})()
        """
    }
}

struct SharedWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let holder = NSView()
        holder.autoresizesSubviews = true
        return holder
    }
    func updateNSView(_ holder: NSView, context: Context) {
        let view = BrowserCenter.shared.ensure()
        if view.superview !== holder {
            view.removeFromSuperview()
            view.frame = holder.bounds
            view.autoresizingMask = [.width, .height]
            holder.addSubview(view)
        }
    }
    static func dismantleNSView(_ holder: NSView, coordinator: ()) {
        BrowserCenter.shared.park()
    }
}

struct BrowserPage: View {
    @Environment(\.boxedPage) private var boxed
    @ObservedObject var center = BrowserCenter.shared
    @ObservedObject var model = AppModel.shared
    @State private var returnNote = ""
    private var agentUsing: Bool { center.agentName != nil && !center.userHasControl }
    var body: some View {
        PageFrame(title: nil, wide: true) {
            HStack {
                Btn("‹", kind: .plain) { center.webView?.goBack() }
                Btn("›", kind: .plain) { center.webView?.goForward() }
                Btn("↻", kind: .plain) { center.webView?.reload() }
                EntermField(placeholder: "Adres", text: $center.address).onSubmit { center.load(center.address) }
                Btn("Git", kind: .primary) { center.load(center.address) }
                if center.userHasControl {
                    T("◆ Kontrol Sizde", color: Theme.palette.need, bold: true)
                    Btn("Ajana Geri Ver", kind: .outline, key: "⌘⇧D") { giveBack() }
                } else if agentUsing {
                    Btn("Devral", kind: .outline, key: "⌘⇧D") { center.userHasControl = true }
                }
                Btn("Kapat", kind: .plain) {
                    center.close()
                    model.page = nil
                }
            }
            if let failure = center.failure { T("✕ \(failure)", color: Theme.palette.err) }
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    SharedWebView()
                    if agentUsing {
                        // While an agent drives the page, clicks do not reach it. "Devral" gives them to the user.
                        Color.clear.contentShape(Rectangle()).onTapGesture {}
                    }
                }
                .frame(minHeight: boxed ? 120 : 520)
                VStack(alignment: .leading, spacing: 8) {
                    if center.userHasControl {
                        T("Siz Kullanıyorsunuz", bold: true)
                        Dim("○ Ajan bekliyor. Ajan durdu, tıklamalarınız sayfaya gider.")
                        EntermField(placeholder: "Geri Verirken Ajana Not", text: $returnNote)
                    } else if let agent = center.agentName {
                        T("Ajan Şu An ● Kullanıyor", bold: true)
                        Dim(agent)
                    } else {
                        T("Sayfa Sizde", bold: true)
                        Dim("Ajan kullanmaya başlayınca burada görünür.")
                    }
                    if !center.steps.isEmpty {
                        T("Son Adımlar", bold: true)
                        ForEach(Array(center.steps.enumerated()), id: \.offset) { _, step in Dim("· \(step)") }
                    }
                    Line()
                    Dim("Tarayıcı bilgisayarda çalışır, yalnız kullanılırken yük bindirir. Giriş bilgileri saklanmaz, hesaplara giriş ajanla paylaşılmaz.")
                }
                .frame(width: 280, alignment: .leading)
            }
        }
        .onAppear { _ = center.ensure() }
    }

    private func giveBack() {
        center.userHasControl = false
        guard !returnNote.isEmpty, let name = center.agentName,
              let info = model.sessions.first(where: { model.title(for: $0) == name }) else { return }
        model.connection.sendInput(number: info.number, bytes: Data("[Kullanıcı Tarayıcıyı Geri Verdi] \(returnNote)\r".utf8))
        returnNote = ""
    }
}
