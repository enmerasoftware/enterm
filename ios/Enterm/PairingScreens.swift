import AVFoundation
import SwiftUI

/// 12.0T: nothing is asked before the phone is actually wanted.
struct WelcomeScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Txt("Bilgisayarınıza Bağlanın", style: .title3, weight: .semibold)
            DimTxt("Terminal bilgisayarınızda çalışır. Telefon aynı ekrana bağlanır, bir kez eşleştirmek yeter.")
            Spacer()
            DimTxt("Bilgisayarda: ⋯ › Telefonu Bağla")
            ActionButton("Kodu Okut", style: .primary) { model.pairing = .scanning }
            ActionButton("Bilgisayar Olmadan Görün", style: .plain) { model.startDemo() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.bg)
    }
}

/// 12.1T: the camera, with typing as the way out when there is none.
struct ScanScreen: View {
    @EnvironmentObject var model: PhoneModel
    @State private var typing = false
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { model.cancelPairing() } label: { BackLabel(title: "Geri") }.buttonStyle(.plain)
                Spacer()
                DimTxt("Adım 1 / 2")
            }
            Txt("Bilgisayarla Eşleştir", style: .title3, weight: .semibold)
            DimTxt("Bilgisayarda Enterm'de gösterilen kodu okutun.")
            if typing {
                TextField("", text: $text, prompt: Text("enterm://pair?…").foregroundColor(Palette.dim), axis: .vertical)
                    .font(.mono)
                    .foregroundColor(Palette.text1)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .frame(minHeight: 88, alignment: .topLeading)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hair2))
                if case .failed(let reason) = model.pairing { Txt(reason, color: Palette.err) }
                ActionButton("Kodu Kullan", style: .primary) { _ = model.read(code: text) }
                ActionButton("Kameraya Dön", style: .plain) { typing = false }
            } else {
                CodeCamera { code in _ = model.read(code: code) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hair2))
                ActionButton("Kodu Elle Yaz") { typing = true }
            }
            DimTxt("Oturumlar bilgisayarda çalışır, telefon aynı arayüze bağlanır.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bg)
    }
}

/// 12.2T
struct CompareScreen: View {
    @EnvironmentObject var model: PhoneModel
    let number: String
    let waiting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { model.cancelPairing() } label: { BackLabel(title: "Geri") }.buttonStyle(.plain)
                Spacer()
                DimTxt("Adım 2 / 2")
            }
            Txt("Sayılar Aynı Mı?", style: .title3, weight: .semibold)
            Text(number)
                .font(.monoLarge)
                .foregroundColor(Palette.fg)
                .frame(maxWidth: .infinity, minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hair2))
            DimTxt("Bilgisayarda da bu sayı görünmeli.")
            Txt("Aynı değilse eşleştirmeyin.", color: Palette.limit)
            Spacer()
            if waiting {
                DimTxt("Bilgisayarda Sayılar Aynı'ya basın.")
            } else {
                ActionButton("Evet, Aynı", style: .primary) { model.confirmNumber() }
                ActionButton("Hayır, Vazgeç") { model.cancelPairing() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bg)
    }
}

struct PairingProblem: View {
    @EnvironmentObject var model: PhoneModel
    let reason: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Txt(reason, color: Palette.err)
            ActionButton("Tekrar Dene", style: .primary) { model.pairing = .scanning }
            ActionButton("Vazgeç", style: .plain) { model.cancelPairing() }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.bg)
    }
}

struct CodeCamera: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> CameraController { CameraController(onCode: onCode) }
    func updateUIViewController(_ controller: CameraController, context: Context) {}
}

final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void
    private var delivered = false
    private var preview: AVCaptureVideoPreviewLayer?

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Palette.panel)
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.main.async { self.configure() }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        delivered = true
        onCode(code)
    }
}
