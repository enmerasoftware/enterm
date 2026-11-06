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
        case confirming(number: String)
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
        guard case .compare(_, let number, _) = pairing else { return }
        pairing = .confirming(number: number)
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

    private var relay: String {
#if ENTERM_TEST_DRIVER
        if let value = ProcessInfo.processInfo.environment["ENTERM_RELAY"] { return value }
#endif
        return settings.settings.relayURL
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
                VStack(alignment: .leading, spacing: 8) {
                    Dim("Oturumlar bilgisayarda çalışır, telefon aynı ekrana bağlanır. Bir kez eşleştirmek yeter.")
                    if relay.isEmpty {
                        Dim("Enterm'in aktarım servisi henüz yayında değil. Kendi aktarım adresinizi aşağıya yazın.")
                    } else {
                        Btn("Telefon Eşleştir", kind: .primary) { store.start(relay: relay) }
                    }
                }
                .padding(12)
            }
        case .waiting(let offer, let expires):
            pairingCard(offer: offer, status: "● Telefon Bekleniyor", number: nil, expires: expires)
        case .compare(let offer, let number, let expires):
            pairingCard(offer: offer, status: "◆ Sayıları Karşılaştırın", number: number, expires: expires)
        case .confirming(let number):
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    T(number, bold: true)
                    Dim("Telefonda da Evet, Aynı'ya dokunun.")
                    Btn("Vazgeç", kind: .plain, key: "Esc") { store.cancel() }
                }
                .padding(12)
            }
        case .finished(let name):
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    T("✓ \(name) Bağlandı", bold: true)
                    Btn("Tamam", kind: .plain) { store.pairing = .idle }
                }
                .padding(12)
            }
        case .failed(let reason):
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    T(reason, color: Theme.palette.err)
                    HStack {
                        Btn("Vazgeç", kind: .plain) { store.pairing = .idle }
                        Btn("Yeni Kod", kind: .primary) { store.start(relay: relay) }
                    }
                }
                .padding(12)
            }
        }
    }

    private func pairingCard(offer: String, status: String, number: String?, expires: Date) -> some View {
        Panel {
            PanelHeader(title: "Telefon Eşleştir") { Dim(status) }
            HStack(alignment: .top, spacing: 16) {
                QRCodeView(text: offer).frame(width: 200, height: 200)
                VStack(alignment: .leading, spacing: 8) {
                    T("1. Telefonda Enterm'i açın, Kodu Okut'a dokunun.")
                    T("2. Kodu okutun.")
                    T("3. Telefonda ve burada aynı sayıyı görün:")
                    T(number ?? "··· ···", bold: true)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(expires.timeIntervalSince(context.date)))
                        Dim("Kod 5 dakika geçerli · \(left / 60):\(String(format: "%02d", left % 60)) kaldı")
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Btn("Yeni Kod", kind: .plain) { store.start(relay: relay) }
                        Btn("Kodu Kopyala", kind: .plain) { NotFoundActions.copy(offer) }
                        Btn("Vazgeç", kind: .plain, key: "Esc") { store.cancel() }
                        if number != nil {
                            Btn("Sayılar Aynı", kind: .primary, key: "⏎") { store.confirm() }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder private var devicesPanel: some View {
        if !store.devices.isEmpty {
            Panel {
                PanelHeader(title: "Cihazlar")
                ForEach(store.devices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            T(device.name)
                            Dim(subtitle(device))
                        }
                        Spacer()
                        Dim(device.connected ? "✓ Bağlı" : "○ Bağlı Değil")
                        Btn("Kaldır", kind: .plain) { removing = device }
                    }
                    .padding(12)
                    Line()
                }
                Dim("Telefon bu bilgisayara uçtan uca şifreli bağlanır. Oturumlar telefonda çalışmaz, yalnız görünür.")
                    .padding(12)
            }
        }
    }

    private func subtitle(_ device: DeviceSummary) -> String {
        let format = Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "tr_TR"))
        if device.connected { return "Şu An Bağlı · Eşleşme: \(device.pairedAt.formatted(format))" }
        if let seen = device.lastSeen { return "Son Görülme: \(seen.formatted(format))" }
        return "Eşleşme: \(device.pairedAt.formatted(format))"
    }

    private var relayPanel: some View {
        Panel {
            PanelHeader(title: "Aktarım Adresi")
            VStack(alignment: .leading, spacing: 8) {
                EntermField(placeholder: "wss://aktarim.ornek.com", text: Binding(
                    get: { settings.settings.relayURL },
                    set: { settings.settings.relayURL = $0 }))
                Dim("Şifreli baytları taşır, içeriği okuyamaz. Bildirimler için APNs anahtarı bu serviste durur.")
            }
            .padding(12)
        }
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
