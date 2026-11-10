import AppKit
import EntermCore
import SwiftUI

/// An Android emulator or a phone on USB, through the SDK's own `adb`. The screen is read only while the box is open
/// and only redrawn when it changed; a click becomes a tap, a drag a swipe.
final class AndroidFeed: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let online: Bool
    }
    @Published var devices: [Device] = []
    @Published var avds: [String] = []
    @Published var image: NSImage?
    @Published var note = ""
    private var timer: Timer?
    private var lastData: Data?
    private var busy = false
    /// The device's own pixel size, so a click lands where it was aimed.
    private(set) var pixels = CGSize.zero

    private static let sdk = NSHomeDirectory() + "/Library/Android/sdk"

    private static func find(_ name: String, under folder: String) -> String? {
        let bundled = "\(sdk)/\(folder)/\(name)"
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] where FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)") {
            return "\(dir)/\(name)"
        }
        return nil
    }

    static var adb: String? { find("adb", under: "platform-tools") }
    static var emulator: String? { find("emulator", under: "emulator") }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> (ok: Bool, data: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return (false, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, data)
    }

    func refresh() {
        guard let adb = Self.adb else {
            note = "adb bulunamadı. Android Studio'yu kurun ya da: brew install --cask android-platform-tools"
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let text = String(decoding: Self.run(adb, ["devices", "-l"]).data, as: UTF8.self)
            let list: [Device] = text.split(separator: "\n").dropFirst().compactMap { line in
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count >= 2 else { return nil }
                let model = fields.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") }
                return Device(id: String(fields[0]), name: model ?? String(fields[0]), online: fields[1] == "device")
            }
            let avds = Self.emulator.map { String(decoding: Self.run($0, ["-list-avds"]).data, as: UTF8.self) }?
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("INFO") } ?? []
            DispatchQueue.main.async {
                self?.devices = list
                self?.avds = avds
                self?.note = list.isEmpty && avds.isEmpty ? "Açık cihaz ya da kayıtlı emülatör yok. Android Studio'nun Device Manager'ından bir emülatör oluşturun." : ""
            }
        }
    }

    /// The emulator runs as its own program, so closing Enterm leaves it alone.
    func boot(_ avd: String) {
        guard let emulator = Self.emulator else { return }
        note = "\(avd) Açılıyor, ilk açılış bir dakika sürebilir"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: emulator)
        process.arguments = ["-avd", avd]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.refresh() }
    }

    func startFeed(_ device: Device) {
        stopFeed()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in self?.capture(device) }
        timer.tolerance = 0.4
        self.timer = timer
        capture(device)
    }

    private func capture(_ device: Device) {
        guard !busy, let adb = Self.adb else { return }
        busy = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.run(adb, ["-s", device.id, "exec-out", "screencap", "-p"])
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard result.ok, !result.data.isEmpty, result.data != self.lastData, let image = NSImage(data: result.data) else { return }
                self.lastData = result.data
                if let rep = image.representations.first { self.pixels = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
                self.image = image
            }
        }
    }

    func stopFeed() {
        timer?.invalidate()
        timer = nil
        image = nil
        lastData = nil
    }

    /// `input` takes device pixels; the point comes in as a fraction of the picture.
    func send(_ device: Device, _ arguments: [String]) {
        guard let adb = Self.adb else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.run(adb, ["-s", device.id, "shell", "input"] + arguments)
            DispatchQueue.main.async { self?.capture(device) }
        }
    }

    func tap(_ device: Device, at point: CGPoint) {
        send(device, ["tap", "\(Int(point.x * pixels.width))", "\(Int(point.y * pixels.height))"])
    }

    func swipe(_ device: Device, from start: CGPoint, to end: CGPoint) {
        send(device, ["swipe", "\(Int(start.x * pixels.width))", "\(Int(start.y * pixels.height))",
                      "\(Int(end.x * pixels.width))", "\(Int(end.y * pixels.height))", "250"])
    }

    /// `input text` takes no spaces; `%s` stands for one.
    func type(_ device: Device, _ text: String) {
        let escaped = text.replacingOccurrences(of: " ", with: "%s").replacingOccurrences(of: "'", with: "")
        send(device, ["text", "'\(escaped)'"])
    }
}

struct AndroidPanel: View {
    @StateObject private var feed = AndroidFeed()
    @State private var selected: AndroidFeed.Device?
    @State private var typed = ""
    @State private var dragStart: CGPoint?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if !feed.note.isEmpty { Dim(feed.note).fixedSize(horizontal: false, vertical: true) }
                Panel {
                    MenuList {
                        ForEach(feed.devices) { device in
                            MenuRow(title: device.name, note: device.online ? "● Açık" : "○ Bağlanıyor", selected: selected == device) {
                                selected = device
                                if device.online { feed.startFeed(device) }
                            }
                        }
                        ForEach(feed.avds.filter { avd in !feed.devices.contains { $0.name.replacingOccurrences(of: " ", with: "_") == avd } }, id: \.self) { avd in
                            MenuRow(title: avd.replacingOccurrences(of: "_", with: " "), note: "Başlat", selected: false) { feed.boot(avd) }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Btn("Yenile", kind: .plain) { feed.refresh() }
                    if let device = selected {
                        Btn("Geri", kind: .plain) { feed.send(device, ["keyevent", "KEYCODE_BACK"]) }
                        Btn("Ana Ekran", kind: .plain) { feed.send(device, ["keyevent", "KEYCODE_HOME"]) }
                    }
                }
                if let device = selected {
                    HStack(spacing: 8) {
                        EntermField(placeholder: "Cihaza yaz", text: $typed)
                        Btn("Gönder", kind: .plain) {
                            feed.type(device, typed)
                            typed = ""
                        }
                    }
                }
                Dim("Tıklama dokunma, sürükleme kaydırma olur. Ekran yalnız bu kutu açıkken ve değişince yenilenir.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300)
            if let image = feed.image, let device = selected {
                GeometryReader { geometry in
                    let size = fitted(image.size, in: geometry.size)
                    Image(nsImage: image).resizable().frame(width: size.width, height: size.height).cornerRadius(6)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if dragStart == nil { dragStart = value.startLocation }
                        }.onEnded { value in
                            let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
                            let end = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                            if hypot(value.translation.width, value.translation.height) < 6 {
                                feed.tap(device, at: start)
                            } else {
                                feed.swipe(device, from: start, to: end)
                            }
                            dragStart = nil
                        })
                }
                .frame(maxHeight: 620)
            } else {
                Dim("Açık bir cihaz seçin.")
            }
        }
        .onAppear { feed.refresh() }
        .onDisappear { feed.stopFeed() }
    }

    private func fitted(_ image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
