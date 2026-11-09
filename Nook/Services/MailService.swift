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
        /// Principio del texto (solo en los mas recientes; vacio si no se leyo).
        var preview: String = ""
    }

    /// Un correo entero para leerlo en el notch.
    struct Detail: Equatable {
        let sender: String
        let address: String
        let subject: String
        let date: Date
        let body: String
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
                    set pv to ""
                    if i ≤ 15 then
                        try
                            set c to content of m
                            if length of c > 160 then set c to text 1 thru 160 of c
                            set pv to c
                        end try
                    end if
                    set out to out & (message id of m) & us & (extract name from (sender of m)) & us & (subject of m) & us & ((date received of m) as «class isot» as string) & us & pv & rs
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
                    set pv to ""
                    if i ≤ 15 then
                        try
                            set c to plain text content of m
                            if length of c > 160 then set c to text 1 thru 160 of c
                            set pv to c
                        end try
                    end if
                    set out to out & (id of m as string) & us & who & us & (subject of m) & us & ((time received of m) as «class isot» as string) & us & pv & rs
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
            guard fields.count >= 4, !fields[0].isEmpty else { return nil }
            let subject = fields[2] == "missing value" ? "" : fields[2]
            let preview = fields.count > 4 ? Self.clean(fields[4], lines: false) : ""
            return Message(id: fields[0], sender: fields[1], subject: subject, date: iso.date(from: fields[3]) ?? .distantPast, preview: preview)
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: - Leer, marcar como leido y responder

    /// El correo entero (remitente, direccion, fecha y texto plano).
    func detail(of message: Message) async -> Detail? {
        let script = Self.detailScript(for: source, id: message.id)
        return await withCheckedContinuation { continuation in
            queue.async {
                guard case let .ok(text) = Self.run(script) else { return continuation.resume(returning: nil) }
                continuation.resume(returning: Self.parseDetail(text))
            }
        }
    }

    /// Marca el correo como leido en su app y lo quita de la lista.
    func markRead(_ message: Message) {
        let script = Self.actionScript(for: source, id: message.id, action: source == .mail ? "set read status of m to true" : "set is read of m to true")
        messages.removeAll { $0.id == message.id }
        seen?.remove(message.id)
        queue.async { _ = Self.run(script) }
    }

    /// Abre la ventana de respuesta en Mail u Outlook.
    func reply(to message: Message) {
        let action = source == .mail
            ? "activate\nreply m with opening window"
            : "activate\nset r to reply to m\nopen r"
        let script = Self.actionScript(for: source, id: message.id, action: action)
        queue.async { _ = Self.run(script) }
    }

    /// `message id` de Mail va entre comillas (se escapan); el de Outlook es un numero.
    nonisolated private static func target(_ source: Source, id: String) -> String {
        switch source {
        case .mail:
            let escaped = id.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "first message of inbox whose message id is \"\(escaped)\""
        case .outlook:
            return "message id \(id.filter(\.isNumber))"
        }
    }

    nonisolated private static func actionScript(for source: Source, id: String, action: String) -> String {
        "tell application \"\(source.appName)\"\nset m to \(target(source, id: id))\n\(action)\nend tell"
    }

    nonisolated private static func detailScript(for source: Source, id: String) -> String {
        switch source {
        case .mail:
            return """
            tell application "Mail"
                set us to character id 31
                set m to \(target(source, id: id))
                set s to sender of m
                return (extract name from s) & us & (extract address from s) & us & (subject of m) & us & ((date received of m) as «class isot» as string) & us & (content of m)
            end tell
            """
        case .outlook:
            return """
            tell application "Microsoft Outlook"
                set us to character id 31
                set m to \(target(source, id: id))
                set who to ""
                set addr to ""
                try
                    set s to sender of m
                    set who to name of s
                    set addr to address of s
                end try
                return who & us & addr & us & (subject of m) & us & ((time received of m) as «class isot» as string) & us & (plain text content of m)
            end tell
            """
        }
    }

    nonisolated static func parseDetail(_ text: String) -> Detail? {
        let fields = text.split(separator: "\u{1F}", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5 else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        iso.timeZone = .current
        let missing: (String) -> String = { $0 == "missing value" ? "" : $0 }
        let body = String(clean(missing(fields[4]), lines: true).prefix(20_000))
        return Detail(sender: missing(fields[0]), address: missing(fields[1]), subject: missing(fields[2]),
                      date: iso.date(from: fields[3]) ?? .distantPast, body: body)
    }

    /// Quita los saltos de linea de mas. Para la vista previa, todo en una linea.
    nonisolated static func clean(_ text: String, lines: Bool) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if !lines {
            return normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        var result: [Substring] = []
        var blank = 0
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            blank = trimmed.isEmpty ? blank + 1 : 0
            if blank <= 1 { result.append(line) }
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
