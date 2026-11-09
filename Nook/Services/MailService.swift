import AppKit
import Observation

/// Bandeja de entrada: los correos sin leer (remitente, asunto y hora) de Mail o de
/// Outlook, leidos por AppleScript. Solo se consulta la app si ya esta abierta: Nook
/// no la lanza por su cuenta. No guarda nada: lo que se ve sale de la app cada vez.
@Observable
@MainActor
final class MailService {
    enum Source: String, CaseIterable, Identifiable {
        case mail, outlook
        var id: String { rawValue }
        var bundleID: String { self == .mail ? "com.apple.mail" : "com.microsoft.Outlook" }
        var appName: String { self == .mail ? "Mail" : "Microsoft Outlook" }
    }

    enum State: Equatable {
        case idle
        case ok
        /// La app no esta abierta.
        case notRunning
        /// Falta el permiso de Automatizacion (Ajustes del Sistema).
        case denied
        /// La app no responde a AppleScript (el Outlook nuevo).
        case unsupported
    }

    struct Message: Identifiable, Equatable {
        let id: String
        let sender: String
        let subject: String
        let date: Date
    }

    private(set) var messages: [Message] = []
    private(set) var state: State = .idle
    /// Llega un correo sin leer que no estaba antes (para el aviso del notch).
    @ObservationIgnored var onNew: ((Message) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var seen: Set<String>?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private let queue = DispatchQueue(label: "com.diegoperez.nook.mail")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var source: Source {
        Source(rawValue: defaults.string(forKey: SettingsKey.mailSource) ?? "") ?? .mail
    }

    var isEnabled: Bool { defaults.bool(forKey: SettingsKey.mailEnabled) }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard isEnabled, !loading else { return }
        let source = source
        guard NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first != nil else {
            state = .notRunning
            messages = []
            return
        }
        loading = true
        let script = Self.script(for: source)
        queue.async {
            let result = Self.run(script)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(result, from: source) }
            }
        }
    }

    /// Abre la app (en segundo plano, sin ventana delante) para poder leer el correo.
    func launchSource() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func open(_ message: Message) {
        switch source {
        case .mail:
            let id = message.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? message.id
            if let url = URL(string: "message://%3c\(id)%3e") { NSWorkspace.shared.open(url) }
        case .outlook:
            let id = message.id.filter(\.isNumber)
            queue.async {
                _ = Self.run("tell application \"Microsoft Outlook\"\nactivate\nopen message id \(id)\nend tell")
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - AppleScript

    private enum Result { case ok(String), denied, unsupported, notRunning }

    private func apply(_ result: Result, from source: Source) {
        loading = false
        guard source == self.source else { return refresh() }
        switch result {
        case let .ok(text):
            let parsed = Self.parse(text)
            if let seen {
                for message in parsed where !seen.contains(message.id) { onNew?(message) }
            }
            seen = Set(parsed.map(\.id))
            messages = parsed
            state = .ok
        case .denied: state = .denied; messages = []
        case .unsupported: state = .unsupported; messages = []
        case .notRunning: state = .notRunning; messages = []
        }
    }

    nonisolated private static func run(_ source: String) -> Result {
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            switch error?[NSAppleScript.errorNumber] as? Int {
            case -1743, -1744: return .denied
            case -600, -609: return .notRunning
            default: return .unsupported
            }
        }
        return .ok(output.stringValue ?? "")
    }

    /// Campos separados por el caracter 31 y correos por el 30 (no salen en asuntos).
    private static func script(for source: Source) -> String {
        switch source {
        case .mail:
            return """
            tell application "Mail"
                set us to character id 31
                set rs to character id 30
                set out to ""
                set msgs to (messages of inbox whose read status is false)
                set n to count of msgs
                if n > 40 then set n to 40
                repeat with i from 1 to n
                    set m to item i of msgs
                    set out to out & (message id of m) & us & (extract name from (sender of m)) & us & (subject of m) & us & ((date received of m) as «class isot» as string) & rs
                end repeat
                return out
            end tell
            """
        case .outlook:
            return """
            tell application "Microsoft Outlook"
                set us to character id 31
                set rs to character id 30
                set out to ""
                set msgs to (messages of inbox whose is read is false)
                set n to count of msgs
                if n > 40 then set n to 40
                repeat with i from 1 to n
                    set m to item i of msgs
                    set who to ""
                    try
                        set s to sender of m
                        set who to name of s
                        if who is missing value or who is "" then set who to address of s
                    end try
                    set out to out & (id of m as string) & us & who & us & (subject of m) & us & ((time received of m) as «class isot» as string) & rs
                end repeat
                return out
            end tell
            """
        }
    }

    /// Mas recientes primero.
    nonisolated static func parse(_ text: String) -> [Message] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        iso.timeZone = .current
        return text.split(separator: "\u{1E}").compactMap { record in
            let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, !fields[0].isEmpty else { return nil }
            let subject = fields[2] == "missing value" ? "" : fields[2]
            return Message(id: fields[0], sender: fields[1], subject: subject, date: iso.date(from: fields[3]) ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }
}
