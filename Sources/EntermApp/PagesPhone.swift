import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import EntermCore
import SwiftUI

/// Pairing and paired devices. Everything secret stays in the session service.
final class PhoneStore: ObservableObject {
    static let shared = PhoneStore()
    enum Pairing: Equatable {
        case idle
        case waiting(offer: String, expires: Date)
        case compare(offer: String, number: String, expires: Date)
        case confirming(offer: String, number: String, expires: Date)
        case finished(String)
        case failed(String)
    }
    @Published var pairing = Pairing.idle
    @Published var devices: [DeviceSummary] = []
    private let decoder = JSONDecoder()

    func loadDevices() {
        AppModel.shared.connection.request(WireMessage(op: "devices")) { [weak self] reply in self?.devicesChanged(reply.text) }
    }

    func devicesChanged(_ text: String?) {
        guard let data = text?.data(using: .utf8), let list = try? decoder.decode([DeviceSummary].self, from: data) else { return }
        devices = list
    }

    func start(relay: String) {
        var message = WireMessage(op: "pairStart")
        message.text = relay
        AppModel.shared.connection.request(message) { [weak self] reply in
            guard let offer = reply.text else { return }
            self?.pairing = .waiting(offer: offer, expires: Date().addingTimeInterval(300))
        }
    }

    func confirm() {
        guard case .compare(let offer, let number, let expires) = pairing else { return }
        pairing = .confirming(offer: offer, number: number, expires: expires)
        AppModel.shared.connection.send(WireMessage(op: "pairConfirm"))
    }

    func cancel() {
        AppModel.shared.connection.send(WireMessage(op: "pairCancel"))
        pairing = .idle
    }

    func remove(_ id: String) {
        var message = WireMessage(op: "deviceRemove")
        message.text = id
        AppModel.shared.connection.send(message)
    }

    func pairingChanged(state: String, detail: String?) {
        switch (state, pairing) {
        case ("compare", .waiting(let offer, let expires)):
            pairing = .compare(offer: offer, number: detail ?? "", expires: expires)
        case ("finished", _):
            pairing = .finished(detail ?? "Telefon")
        case ("failed", _):
            pairing = .failed("Bağlantı Kesildi. Yeni Kod Alın.")
        case ("expired", _):
            pairing = .failed("Kodun Süresi Doldu. Yeni Kod Alın.")
        default:
            break
        }
    }
}

struct PhonePage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = PhoneStore.shared
    @ObservedObject var settings = SettingsStore.shared
    @State private var removing: DeviceSummary?
    @State private var editingRelay = false

    private var relay: String {
#if ENTERM_TEST_DRIVER
        if let value = ProcessInfo.processInfo.environment["ENTERM_RELAY"] { return value }
#endif
        // A pasted address often carries a space; a URL with one never opens.
        return settings.settings.relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        PageFrame(title: "Telefonu Bağla", centered: true) {
            if let removing {
                removal(removing)
            } else {
                pairingPanel
                devicesPanel
                relayPanel
            }
        }
        .onAppear { store.loadDevices() }
    }

    @ViewBuilder private var pairingPanel: some View {
        switch store.pairing {
        case .idle:
            Panel {
                HStack(alignment: .center, spacing: 20) {
                    Symbol("iphone.gen3", color: Theme.palette.need, size: 40)
                        .frame(width: 64, height: 64)
                        .background(Color(Theme.palette.fill))
                        .cornerRadius(Theme.cornerCard)
                    VStack(alignment: .leading, spacing: 6) {
                        T("Oturumlarınız Cebinizde", bold: true, style: .section)
                        Dim("Onay isteyen ajanı, biten işi ve limitleri telefondan görün, oradan yanıtlayın. Oturumlar bu bilgisayarda çalışmaya devam eder; bağlantı uçtan uca şifrelidir.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Btn("Telefon Eşleştir", kind: .primary) { store.start(relay: relay) }
                        .disabled(relay.isEmpty)
                }
                .padding(20)
            }
        case .waiting(let offer, let expires):
            pairingCard(offer: offer, step: 0, number: nil, expires: expires)
        case .compare(let offer, let number, let expires):
            pairingCard(offer: offer, step: 1, number: number, expires: expires)
        case .confirming(let offer, let number, let expires):
            pairingCard(offer: offer, step: 2, number: number, expires: expires)
        case .finished(let name):
            Panel {
                HStack(spacing: 16) {
                    Symbol("checkmark.circle.fill", color: Theme.palette.g1, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        T("\(name) Bağlandı", bold: true, style: .section)
                        Dim("Oturumlar artık telefonda. Bildirimler ve onaylar oraya da gider.")
                    }
                    Spacer(minLength: 0)
                    Btn("Tamam", kind: .primary, key: "⏎") { store.pairing = .idle }
                }
                .padding(20)
            }
        case .failed(let reason):
            Panel(border: Theme.palette.err.withAlphaComponent(0.55)) {
                HStack(spacing: 16) {
                    Symbol("exclamationmark.triangle", color: Theme.palette.err, size: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        T(reason, bold: true)
                        Dim("Aktarım adresi doğruysa yeni bir kodla tekrar deneyin.")
                    }
                    Spacer(minLength: 0)
                    Btn("Vazgeç", kind: .plain) { store.pairing = .idle }
                    Btn("Yeni Kod", kind: .primary) { store.start(relay: relay) }
                }
                .padding(20)
            }
        }
    }

    /// One card for the whole handshake: the steps on top, the code on the left, what to do now on the right.
    private func pairingCard(offer: String, step: Int, number: String?, expires: Date) -> some View {
        Panel {
            PanelHeader(title: "Telefon Eşleştir") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(expires.timeIntervalSince(context.date)))
                    Dim("Kod \(left / 60):\(String(format: "%02d", left % 60)) geçerli")
                }
            }
            PairingSteps(current: step).padding(.horizontal, 20).padding(.vertical, 12)
            Line()
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 10) {
                    QRCodeView(text: offer)
                        .frame(width: 216, height: 216)
                        .opacity(step == 0 ? 1 : 0.35)
                    HStack(spacing: 8) {
                        Btn("Yeni Kod", kind: .plain) { store.start(relay: relay) }
                        Btn("Kodu Kopyala", kind: .plain) { NotFoundActions.copy(offer) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    switch step {
                    case 0:
                        T("Telefonda Enterm'i Açın", bold: true, style: .section)
                        Dim("Eşleştir ekranında Kodu Okut'a dokunun ve soldaki kodu okutun. Kamera kullanılamıyorsa Kodu Kopyala ile bağlantıyı telefona gönderin.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Circle().fill(Color(Theme.palette.need)).frame(width: 7, height: 7).neon(Theme.palette.need, radius: 3)
                            T("Telefon Bekleniyor", color: Theme.palette.text2, style: .secondary, weight: .semibold)
                        }
                    case 1:
                        T("Sayıları Karşılaştırın", bold: true, style: .section)
                        Dim("Telefonda da aynı sayı görünmeli. Aynıysa onaylayın.")
                            .fixedSize(horizontal: false, vertical: true)
                        PairingNumber(number: number ?? "")
                        Dim("Sayılar farklıysa Vazgeç'e basın: araya başka biri girmiş olabilir.")
                            .fixedSize(horizontal: false, vertical: true)
                    default:
                        T("Telefonda Onaylayın", bold: true, style: .section)
                        PairingNumber(number: number ?? "")
                        Dim("Telefonda Evet, Aynı'ya dokunun. Bağlantı kendiliğinden tamamlanır.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        if step == 1 {
                            Btn("Sayılar Aynı", kind: .primary, key: "⏎") { store.confirm() }
                        }
                        Btn("Vazgeç", kind: .plain, key: "Esc") { store.cancel() }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }

    @ViewBuilder private var devicesPanel: some View {
        if !store.devices.isEmpty {
            Panel {
                PanelHeader(title: "Cihazlar")
                ForEach(store.devices) { device in
                    Line()
                    HStack(spacing: 12) {
                        Symbol("iphone.gen3", color: Theme.palette.text2, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            T(device.name, weight: .semibold)
                            Dim(subtitle(device))
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(Color(device.connected ? Theme.palette.g1 : Theme.palette.text3)).frame(width: 7, height: 7)
                            T(device.connected ? "Bağlı" : "Bağlı Değil", color: Theme.palette.text2, style: .secondary)
                        }
                        Btn("Kaldır", kind: .plain) { removing = device }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func subtitle(_ device: DeviceSummary) -> String {
        let format = Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "tr_TR"))
        if device.connected { return "Şu An Bağlı · Eşleşme: \(device.pairedAt.formatted(format))" }
        if let seen = device.lastSeen { return "Son Görülme: \(seen.formatted(format))" }
        return "Eşleşme: \(device.pairedAt.formatted(format))"
    }

    /// Most people never touch it, so it is one line; the field opens only to change it.
    private var relayPanel: some View {
        Panel {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    T("Aktarım Servisi", weight: .semibold)
                    Dim("Şifreli baytları taşır, içeriği okuyamaz.")
                }
                Spacer(minLength: 0)
                if !editingRelay {
                    T(Self.host(relay), color: Theme.palette.text2, style: .secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if relay == AppSettings().relayURL { Dim("Enmera") }
                }
                Btn(editingRelay ? "Bitti" : "Değiştir", kind: .plain) { editingRelay.toggle() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            if editingRelay {
                Line()
                VStack(alignment: .leading, spacing: 8) {
                    EntermField(placeholder: "wss://aktarim.ornek.com", text: Binding(
                        get: { settings.settings.relayURL },
                        set: { settings.settings.relayURL = $0 }))
                    HStack {
                        Dim("Kendi aktarım servisinizi kurmak için: relay/DEPLOY.md")
                        Spacer(minLength: 0)
                        if relay != AppSettings().relayURL {
                            Btn("Varsayılana Dön", kind: .plain) { settings.settings.relayURL = AppSettings().relayURL }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private static func host(_ address: String) -> String {
        URL(string: address)?.host ?? (address.isEmpty ? "Yok" : address)
    }

    private func removal(_ device: DeviceSummary) -> some View {
        Panel {
            PanelHeader(title: "\(device.name) Kaldırılsın Mı?") { T("✕ Geri Alınamaz", color: Theme.palette.err) }
            VStack(alignment: .leading, spacing: 8) {
                Dim("Bu telefon oturumları göremez ve onay veremez. Tekrar kullanmak için yeniden eşleştirirsiniz.")
                Dim("Oturumlar bilgisayarda çalışmaya devam eder.")
                HStack {
                    Btn("Vazgeç", kind: .plain, key: "Esc") { removing = nil }
                    Btn("Cihazı Kaldır", kind: .danger) {
                        store.remove(device.id)
                        removing = nil
                    }
                }
            }
            .padding(12)
        }
    }
}

/// Okut, Karşılaştır, Onayla: done steps carry a tick, the current one the accent, the rest stay quiet.
private struct PairingSteps: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let current: Int
    private let titles = ["Kodu Okutun", "Sayıları Karşılaştırın", "Telefonda Onaylayın"]
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 10) {
            ForEach(titles.indices, id: \.self) { index in
                let done = index < current
                let now = index == current
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(now ? palette.need : (done ? palette.fill : .clear)))
                            .overlay(Circle().stroke(Color(now || done ? .clear : palette.hair2)))
                            .frame(width: 22, height: 22)
                        if done {
                            Symbol("checkmark", color: palette.g1, size: 12)
                        } else {
                            T("\(index + 1)", color: now ? palette.btnfg : palette.text3, style: .hint, weight: .bold)
                        }
                    }
                    T(titles[index], color: now ? palette.text1 : (done ? palette.text2 : palette.text3),
                      style: .secondary, weight: now ? .semibold : .regular)
                        .lineLimit(1)
                }
                if index < titles.count - 1 {
                    Rectangle().fill(Color(done ? palette.g1.withAlphaComponent(0.5) : palette.hair)).frame(height: 1)
                        .frame(minWidth: 16, maxWidth: .infinity)
                }
            }
        }
    }
}

/// The comparison number, large and in fixed-width digits so the two screens are easy to read side by side.
private struct PairingNumber: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let number: String
    var body: some View {
        Text(number.isEmpty ? "··· ···" : number)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundColor(Color(Theme.palette.text1))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(Theme.palette.fill))
            .cornerRadius(Theme.cornerCard)
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Color(Theme.palette.hair2)))
            .textSelection(.enabled)
    }
}

struct QRCodeView: View {
    let text: String
    var body: some View {
        if let image = Self.image(text) {
            Image(nsImage: image).interpolation(.none).resizable().padding(8).background(Color.white).cornerRadius(Theme.cornerControl)
        } else {
            Dim("Kod Üretilemedi")
        }
    }

    private static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: output.extent.size)
    }
}
