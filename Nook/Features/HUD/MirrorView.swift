import AVFoundation
import SwiftUI

/// Espejo: la camara en vivo para verte antes de una llamada. Solo se enciende
/// mientras esta a la vista y no se graba ni se guarda nada.
struct MirrorView: View {
    @State private var camera = MirrorCamera()

    var body: some View {
        ZStack {
            Color.black
            switch camera.state {
            case .running:
                CameraPreview(session: camera.session)
            case .starting:
                ProgressView().controlSize(.small)
            case .denied:
                message(icon: "video.slash.fill", text: "Nook no tiene permiso para la cámara") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .unavailable:
                message(icon: "video.slash.fill", text: "No hay cámara disponible", action: nil)
            }
        }
        .frame(width: 320, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(10)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func message(icon: String, text: LocalizedStringKey, action: (() -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
            Text(text).font(AppTypography.bodyStrong).multilineTextAlignment(.center)
            if let action {
                Button("Abrir Ajustes del Sistema", action: action).controlSize(.small)
            }
        }
        .foregroundStyle(.white)
        .padding()
    }
}

@Observable
@MainActor
final class MirrorCamera {
    enum State { case starting, running, denied, unavailable }

    private(set) var state = State.starting
    let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.diegoperez.nook.mirror")
    @ObservationIgnored private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in granted ? self.run() : (self.state = .denied) }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    private func run() {
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                state = .unavailable
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .medium
            session.addInput(input)
            session.commitConfiguration()
            configured = true
        }
        let session = session
        queue.async {
            session.startRunning()
            Task { @MainActor in self.state = .running }
        }
    }
}

/// Vista previa de AVFoundation, en espejo como en FaceTime.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
