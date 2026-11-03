import AppKit
import AVFoundation
import EntermCore
import Speech

/// Hold ⌃⌘ to talk. Nothing is sent by itself: the text lands in the prompt and the user presses Enter.
/// The microphone closes the moment the keys are released, a short tap never opens it.
final class VoiceInput {
    static let shared = VoiceInput()
    private var holdTimer: Timer?
    private var listening = false
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var targetNumber: UInt32?
    private var keyMonitor: Any?

    func flagsChanged(_ event: NSEvent) {
        guard SettingsStore.shared.settings.voiceEnabled else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.control, .command] {
            guard holdTimer == nil, !listening else { return }
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.holdTimer = nil
                self?.begin()
            }
            // Any other key within the hold time means a shortcut, not speech.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] key in
                self?.cancelHold()
                return key
            }
        } else {
            cancelHold()
            if listening { finish(send: true) }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func cancelListening() {
        if listening { finish(send: false) }
    }

    private func begin() {
        cancelHold()
        guard let number = AppModel.shared.focused else { return }
        targetNumber = number
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    AppModel.shared.hint = "Konuşma Tanıma İzni Yok: Sistem Ayarları"
                    return
                }
                self?.startEngine()
            }
        }
    }

    private func startEngine() {
        let language = SettingsStore.shared.settings.voiceLanguage
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
            AppModel.shared.hint = "Bu Dilde Dikte Şu An Yok"
            return
        }
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            AppModel.shared.hint = "Mikrofon Bulunamadı"
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            AppModel.shared.hint = "Mikrofon İzni Yok: Sistem Ayarları"
            return
        }
        transcript = ""
        self.engine = engine
        self.request = request
        listening = true
        AppModel.shared.hint = "● Dinliyor · Bırakınca Biter"
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            self.transcript = result.bestTranscription.formattedString
        }
    }

    private func finish(send: Bool) {
        listening = false
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        request?.endAudio()
        AppModel.shared.hint = send ? "Çeviriyor" : nil
        let number = targetNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.task?.cancel()
            self.task = nil
            self.request = nil
            AppModel.shared.hint = nil
            if send, let number, !self.transcript.isEmpty {
                AppModel.shared.connection.sendInput(number: number, bytes: Data(self.transcript.utf8))
            }
        }
    }
}
