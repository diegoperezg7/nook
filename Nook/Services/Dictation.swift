import AVFoundation
import Observation
import Speech

/// Dictado: se habla, el texto se ve en el notch y al parar se copia al
/// portapapeles. El reconocimiento se hace en el Mac cuando el idioma lo permite.
@Observable
@MainActor
final class Dictation {
    private(set) var isListening = false
    private(set) var transcript = ""
    /// Al parar con texto: se copia y se avisa.
    @ObservationIgnored var onFinish: ((String) -> Void)?
    /// Sin permiso de micro o de reconocimiento.
    @ObservationIgnored var onDenied: (() -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silence: DispatchWorkItem?

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening else { return }
        Task {
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            let mic = await AVCaptureDevice.requestAccess(for: .audio)
            guard speech, mic else { onDenied?(); return }
            begin()
        }
    }

    func stop() {
        guard isListening else { return }
        silence?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isListening = false
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.finish()
        task = nil
        request = nil
        if !text.isEmpty { onFinish?(text) }
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { onDenied?(); return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        transcript = ""

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); onDenied?(); return }
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isListening else { return }
                    if let text { self.transcript = text }
                    if done { self.stop() } else { self.scheduleSilenceStop() }
                }
            }
        }
        scheduleSilenceStop()
    }

    /// Para solo tras 4 s sin palabras nuevas.
    private func scheduleSilenceStop() {
        silence?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        silence = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
