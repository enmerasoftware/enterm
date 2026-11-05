import AppKit
import AVFoundation
import EntermCore
import SwiftUI

/// Local speech to text. The program runs only for the seconds of one dictation, so its memory is gone right after.
/// The sound stays on this Mac. A model is downloaded only when the person asks.
final class WhisperCenter: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = WhisperCenter()

    struct Model: Identifiable {
        let id: String
        let title: String
        let size: String
        var file: String { "ggml-\(id).bin" }
        var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")! }
    }

    static let models = [
        Model(id: "tiny", title: "Küçük", size: "75 MB"),
        Model(id: "base", title: "Orta", size: "142 MB"),
        Model(id: "small", title: "İyi", size: "466 MB"),
        Model(id: "large-v3-turbo", title: "En İyi", size: "1,6 GB"),
    ]

    @Published var downloading: String?
    @Published var progress = 0.0
    @Published var failure = ""
    private var session: URLSession?

    private var folder: URL { EntermPaths.support.appendingPathComponent("whisper", isDirectory: true) }

    func path(of model: Model) -> URL { folder.appendingPathComponent(model.file) }
    func isReady(_ model: Model) -> Bool { FileManager.default.fileExists(atPath: path(of: model).path) }

    /// The program itself: inside the app when it was built with it, otherwise the one on this Mac.
    var program: String? {
        var places = ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        if let bundled = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("whisper-cli").path { places.insert(bundled, at: 0) }
        return places.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var chosen: Model? {
        let id = SettingsStore.shared.settings.whisperModel
        return Self.models.first { $0.id == id && isReady($0) } ?? Self.models.first(where: isReady)
    }

    func download(_ model: Model) {
        guard downloading == nil else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        downloading = model.id
        progress = 0
        failure = ""
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.session = session
        session.downloadTask(with: model.url).resume()
    }

    func remove(_ model: Model) {
        try? FileManager.default.removeItem(at: path(of: model))
        objectWillChange.send()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytes: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloading, let model = Self.models.first(where: { $0.id == id }) else { return }
        if (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 {
            try? FileManager.default.removeItem(at: path(of: model))
            try? FileManager.default.moveItem(at: location, to: path(of: model))
            SettingsStore.shared.settings.whisperModel = id
        } else {
            failure = "Model İndirilemedi"
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { failure = "Model İndirilemedi" }
        downloading = nil
        self.session = nil
        session.finishTasksAndInvalidate()
    }

    /// Runs the program on a recording and answers with the words.
    func transcribe(_ file: URL, language: String, completion: @escaping (String) -> Void) {
        guard let program, let model = chosen else {
            completion("")
            return
        }
        let code = language.split(separator: "-").first.map(String.init) ?? "auto"
        let modelPath = path(of: model).path
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: program)
            process.arguments = ["-m", modelPath, "-f", file.path, "-l", code, "-nt", "-np", "-t", "4"]
            let pipe = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var text = ""
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            try? FileManager.default.removeItem(at: file)
            DispatchQueue.main.async { completion(text) }
        }
    }
}

/// Writes the microphone to a 16 kHz mono file, the shape whisper expects.
final class WhisperRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("enterm-dikte-\(UUID().uuidString).wav")

    func start() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: target),
              let file = try? AVAudioFile(forWriting: url, settings: target.settings, commonFormat: .pcmFormatInt16, interleaved: true) else { return false }
        self.converter = converter
        self.file = file
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let file = self.file else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / format.sampleRate) + 16
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var given = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if given {
                    status.pointee = .noDataNow
                    return nil
                }
                given = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil { try? file.write(from: output) }
        }
        engine.prepare()
        do { try engine.start() } catch { return false }
        return true
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        file = nil
        converter = nil
    }
}

struct VoiceSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var whisper = WhisperCenter.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Konuşarak Yazma", note: "Basılı tutun, konuşun, bırakın. Kullanılmadıkça yük bindirmez.") {
                    HStack {
                        Key("⌃⌘")
                        Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.voiceEnabled)
                    }
                }
                SettingsLine(title: "Dil") {
                    Seg(options: [("tr-TR", "Türkçe"), ("en-US", "English")], value: $store.settings.voiceLanguage)
                }
                SettingsLine(title: "Çeviren", note: store.settings.voiceEngine == "whisper" ? "Ses bilgisayardan çıkmaz. Yalnız dikte sırasında çalışır." : "İşletim sisteminin hizmeti. İndirme yok, mümkünse cihazda işlenir.") {
                    Seg(options: [("system", "Sistem Diktesi"), ("whisper", "Yerel Whisper")], value: $store.settings.voiceEngine)
                }
            }
            if store.settings.voiceEngine == "whisper" {
                SectionHead(title: "Whisper Modelleri", note: "Büyüdükçe daha iyi anlar, daha geç yazar. İstediğinizi indirin.")
                if whisper.program == nil {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            T("whisper-cli Bu Bilgisayarda Yok", bold: true)
                            CommandBox(text: "brew install whisper-cpp")
                            Btn("Yeni Terminalde Çalıştır") {
                                AppModel.shared.page = nil
                                AppModel.shared.newTerminal(cwd: NSHomeDirectory(), startup: "brew install whisper-cpp")
                            }
                        }
                        .padding(16)
                    }
                }
                Panel {
                    ForEach(WhisperCenter.models) { model in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                T(model.title)
                                Dim(model.size)
                            }
                            Spacer()
                            if whisper.downloading == model.id {
                                Meter(percent: whisper.progress * 100).frame(width: 120)
                                Dim("%\(Int(whisper.progress * 100))")
                            } else if whisper.isReady(model) {
                                if store.settings.whisperModel == model.id {
                                    T("Seçili", color: Theme.palette.need, style: .secondary, weight: .semibold)
                                } else {
                                    Btn("Seç", kind: .plain) { store.settings.whisperModel = model.id }
                                }
                                Btn("Sil", kind: .plain) { whisper.remove(model) }
                            } else {
                                Btn("İndir") { whisper.download(model) }.disabled(whisper.downloading != nil)
                            }
                        }
                        .settingsRow()
                    }
                }
                if !whisper.failure.isEmpty { T(whisper.failure, color: Theme.palette.err, style: .secondary) }
            }
            Dim("Metni siz gönderirsiniz: Enter'a siz basarsınız. Tuş bırakılınca mikrofon hemen kapanır.")
        }
    }
}
