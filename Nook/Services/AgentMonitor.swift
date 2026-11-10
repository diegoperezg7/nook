import AppKit
import Foundation
import Observation
import SQLite3

/// Sesiones de agentes de IA en este Mac y lo que se sabe de su consumo.
///
/// Fuentes (solo metadatos; nunca transcripts, titulos ni credenciales):
/// - Claude Code (terminal y extension de VS Code): `~/.claude/sessions/<pid>.json`,
///   que el propio Claude Code mantiene con `status` (busy / idle / waiting),
///   `waitingFor` y `entrypoint` (`cli` o `claude-vscode`).
/// - Codex: `~/.codex/state_5.sqlite` (tabla `threads`: origen, modelo, tokens) y
///   `~/.codex/thread_history_1.sqlite` (tabla `thread_turns`: estado de cada tarea).
/// - Consumo de la suscripcion de Claude: el snapshot JSON que escribe la barra de
///   estado (claude-hud, `display.externalUsageWritePath`) a partir del `rate_limits`
///   oficial que Claude Code le pasa. Sin snapshot, se dice que no hay dato.
@Observable
@MainActor
final class AgentMonitor {
    /// Las sesiones activas (en curso o esperando al usuario) y las de Claude Code que
    /// siguen abiertas tras terminar su turno (`idle` con el proceso vivo). Las
    /// cerradas, interrumpidas o con error no se muestran.
    var sessions: [AgentSession] { allSessions.filter { $0.status.isActive || $0.isOpen } }
    /// Todas, para saber que herramienta se uso por ultima vez (consumo).
    private(set) var allSessions: [AgentSession] = []
    private(set) var claudeUsage: SubscriptionUsage?
    /// Codex expone el consumo solo por su app-server: pendiente de decidir (fase 2).
    let codexUsage: SubscriptionUsage? = nil

    /// Herramientas que se estan usando: con una sesion en curso o pendiente, o con
    /// actividad en la ultima media hora. Si no hay ninguna, la ultima usada.
    var activeFamilies: [AgentSession.Family] {
        AgentSources.activeFamilies(in: allSessions)
    }

    func usage(for family: AgentSession.Family) -> SubscriptionUsage? {
        family == .claude ? claudeUsage : codexUsage
    }

    @ObservationIgnored private let home: URL
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var timer: Timer?
    /// Un agente termina o se queda esperando al usuario (para el aviso del notch).
    @ObservationIgnored var onChange: ((AgentSession, AgentEvent) -> Void)?
    /// Una ventana de consumo cruza el 80 % o el 95 % (para el aviso del notch).
    @ObservationIgnored var onUsageAlert: ((SubscriptionUsage.Window, SubscriptionUsage) -> Void)?
    /// Ultima lectura valida del consumo: un snapshot a medio escribir no rearma los avisos.
    @ObservationIgnored private var lastUsage: SubscriptionUsage?

    /// Lee las sesiones cada pocos segundos (son ficheros pequeños) para avisar.
    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }

    /// Trae delante la app donde corre la sesion (terminal o editor). Dentro de tmux
    /// tambien elige su ventana y su panel, y sube desde el cliente que la muestra.
    func focus(_ session: AgentSession) {
        if let target = session.tmux, let tmux = AgentSources.tmuxPath {
            Task.detached(priority: .userInitiated) {
                let client = AgentSources.selectTmux(target, tmux: tmux)
                await MainActor.run {
                    if let client, let app = AgentSources.hostApp(of: client) { app.activate() }
                }
            }
        } else if let pid = session.pid, let app = AgentSources.hostApp(of: pid) {
            app.activate()
        } else if session.tool == .claudeVSCode,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    nonisolated static let claudeUsageSnapshot = ".claude/nook-usage.json"

    init(home: URL = AgentMonitor.realHome) {
        self.home = home
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let home = home
        let snapshot = await Task.detached(priority: .utility) {
            (AgentSources.claudeSessions(home: home) + AgentSources.codexThreads(home: home),
             AgentSources.claudeUsage(at: home.appendingPathComponent(AgentMonitor.claudeUsageSnapshot)))
        }.value
        let sorted = snapshot.0.sorted { $0.updatedAt > $1.updatedAt }
        if hasLoaded {
            for (session, event) in AgentSources.events(from: allSessions, to: sorted) { onChange?(session, event) }
        }
        hasLoaded = true
        if sorted != allSessions { allSessions = sorted }
        if snapshot.1 != claudeUsage { claudeUsage = snapshot.1 }
        if let usage = snapshot.1 {
            for window in UsageAlert.crossings(old: lastUsage, new: usage) { onUsageAlert?(window, usage) }
            lastUsage = usage
        }
    }

    /// Carpeta personal real: dentro del sandbox `NSHomeDirectory()` es el contenedor.
    nonisolated static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}

struct AgentSession: Identifiable, Equatable, Sendable {
    enum Tool: Equatable, Sendable {
        case claudeTerminal, claudeVSCode, claudeOther(String), codex(String)

        var family: Family {
            if case .codex = self { return .codex }
            return .claude
        }
    }

    /// De quien es la suscripcion.
    enum Family: Equatable, Sendable { case claude, codex }

    enum Status: Equatable, Sendable {
        case running
        /// Espera al usuario: permiso, una pregunta, un dialogo...
        case pending(String?)
        case finished
        case interrupted
        case failed
        case unknown(String)

        var isActive: Bool {
            switch self {
            case .running, .pending: return true
            default: return false
            }
        }
    }

    let id: String
    let tool: Tool
    /// Carpeta del proyecto (solo el nombre).
    let project: String?
    let status: Status
    let updatedAt: Date
    /// Tokens de la sesion si la fuente los da (Codex); nil si no los expone.
    let tokens: Int?
    let model: String?
    /// Proceso de la sesion (Claude Code), para llevarte a su terminal.
    var pid: pid_t?
    /// Panel de tmux donde corre ("sesion:@ventana.%panel"), si va dentro de tmux.
    var tmux: String?

    /// Turno terminado pero con el proceso aun vivo: la sesion sigue abierta.
    var isOpen: Bool {
        guard status == .finished, let pid else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}

/// Lo que merece un aviso.
enum AgentEvent: Equatable { case finished, waiting }

/// Consumo de la suscripcion: ventanas con su porcentaje usado.
struct SubscriptionUsage: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    let windows: [Window]
    let updatedAt: Date?
}

extension SubscriptionUsage.Window {
    /// Porcentaje consumido, redondeado y entre 0 y 100.
    var usedRounded: Int { Int(min(max(usedPercent, 0), 100).rounded()) }

    /// Cuando se reinicia: "16:40" si es hoy, "vie 09:00" si es otro dia.
    func resetLabel(now: Date = .now) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        return Calendar.current.isDate(resetsAt, inSameDayAs: now)
            ? resetsAt.formatted(date: .omitted, time: .shortened)
            : resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// Cuando avisar del consumo de la suscripcion.
enum UsageAlert {
    /// Ventanas que suben por encima de algun umbral desde la lectura anterior. Sin
    /// lectura anterior (arranque) no se avisa: solo se fija el estado. Al reiniciarse
    /// la ventana el porcentaje baja y el umbral vuelve a quedar armado.
    static func crossings(old: SubscriptionUsage?, new: SubscriptionUsage,
                          thresholds: [Double] = [80, 95]) -> [SubscriptionUsage.Window] {
        guard let old else { return [] }
        return new.windows.filter { window in
            guard let before = old.windows.first(where: { $0.label == window.label }) else { return false }
            return thresholds.contains { before.usedPercent < $0 && window.usedPercent >= $0 }
        }
    }
}

/// Lectura de las fuentes. Funciones puras sobre una carpeta personal para poder
/// probarlas con datos simulados.
enum AgentSources {
    static func activeFamilies(in sessions: [AgentSession], now: Date = .now) -> [AgentSession.Family] {
        let active = sessions.filter { session in
            switch session.status {
            case .running, .pending: return true
            default: return now.timeIntervalSince(session.updatedAt) < 30 * 60
            }
        }
        let families = [AgentSession.Family.claude, .codex].filter { family in active.contains { $0.tool.family == family } }
        if !families.isEmpty { return families }
        return sessions.max { $0.updatedAt < $1.updatedAt }.map { [$0.tool.family] } ?? []
    }

    // MARK: Claude Code

    static func claudeSessions(home: URL) -> [AgentSession] {
        let folder = home.appendingPathComponent(".claude/sessions", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return claudeSession(from: object)
        }
    }

    /// Solo se usan campos de estado: el nombre de la sesion se ignora a proposito.
    static func claudeSession(from object: [String: Any]) -> AgentSession? {
        guard let id = object["sessionId"] as? String else { return nil }
        let tool: AgentSession.Tool
        switch object["entrypoint"] as? String {
        case "cli": tool = .claudeTerminal
        case "claude-vscode": tool = .claudeVSCode
        case let other: tool = .claudeOther(other ?? "?")
        }
        let status: AgentSession.Status
        switch object["status"] as? String {
        case "busy": status = .running
        case "waiting": status = .pending(object["waitingFor"] as? String)
        case "idle": status = .finished
        case let other: status = .unknown(other ?? "?")
        }
        let millis = (object["statusUpdatedAt"] as? NSNumber) ?? (object["updatedAt"] as? NSNumber)
        return AgentSession(
            id: "claude-" + id,
            tool: tool,
            project: (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent },
            status: status,
            updatedAt: millis.map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? .distantPast,
            tokens: nil,
            model: nil,
            pid: (object["pid"] as? NSNumber).map { pid_t($0.int32Value) },
            tmux: (object["tmux"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// Cambios que avisan: de "en curso" a terminada, o a esperar al usuario. Las
    /// sesiones nuevas no avisan (no se sabe que hacian antes).
    static func events(from old: [AgentSession], to new: [AgentSession]) -> [(AgentSession, AgentEvent)] {
        new.compactMap { session in
            guard let before = old.first(where: { $0.id == session.id })?.status else { return nil }
            switch (before, session.status) {
            case (.running, .finished): return (session, .finished)
            case (.pending, .pending): return nil
            case (_, .pending): return (session, .waiting)
            default: return nil
            }
        }
    }

    nonisolated static var tmuxPath: String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Selecciona la ventana y el panel de tmux ("sesion:@ventana.%panel") y devuelve
    /// el proceso del cliente que muestra esa sesion.
    nonisolated static func selectTmux(_ target: String, tmux: String) -> pid_t? {
        let parts = target.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let session = String(parts[0])
        let rest = parts[1].split(separator: ".", maxSplits: 1)
        if let window = rest.first { run(tmux, ["select-window", "-t", "\(session):\(window)"]) }
        if rest.count == 2 { run(tmux, ["select-pane", "-t", String(rest[1])]) }
        let clients = run(tmux, ["list-clients", "-t", session, "-F", "#{client_activity} #{client_pid}"])
        // El cliente usado mas recientemente, si hay varios.
        return clients.split(separator: "\n")
            .compactMap { line -> (Int, pid_t)? in
                let fields = line.split(separator: " ")
                guard fields.count == 2, let activity = Int(fields[0]), let pid = pid_t(fields[1]) else { return nil }
                return (activity, pid)
            }
            .max { $0.0 < $1.0 }?.1
    }

    @discardableResult
    nonisolated private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// La app (con ventana) de la que cuelga un proceso: se sube por los padres.
    @MainActor
    static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            let parent = info.kp_eproc.e_ppid
            guard parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    static func claudeUsage(at url: URL) -> SubscriptionUsage? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let windows: [SubscriptionUsage.Window] = [("five_hour", "5 h"), ("seven_day", String(localized: "Semana"))].compactMap { key, label in
            guard let window = object[key] as? [String: Any],
                  let used = (window["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            return .init(label: label, usedPercent: used, resetsAt: (window["resets_at"] as? String).flatMap(parseDate))
        }
        guard !windows.isEmpty else { return nil }
        return SubscriptionUsage(windows: windows, updatedAt: (object["updated_at"] as? String).flatMap(parseDate))
    }

    // MARK: Codex

    /// Los hilos de Codex sin archivar mas recientes, con el estado de su ultima tarea.
    static func codexThreads(home: URL, limit: Int = 5) -> [AgentSession] {
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        // Solo columnas de metadatos: ni titulo, ni primer mensaje, ni vista previa.
        let rows = SQLiteReader.rows(
            at: codex.appendingPathComponent("state_5.sqlite"),
            sql: "select id, source, model, tokens_used, updated_at, cwd from threads where archived = 0 order by updated_at desc limit \(limit)"
        )
        let history = codex.appendingPathComponent("thread_history_1.sqlite")
        return rows.compactMap { row in
            guard let id = row[0] as? String else { return nil }
            let source = row[1] as? String ?? ""
            let turn = SQLiteReader.rows(
                at: history,
                sql: "select status from thread_turns where thread_id = ? order by rollout_ordinal desc limit 1",
                bind: [id]
            ).first?.first as? String
            return AgentSession(
                id: "codex-" + id,
                tool: .codex(source.hasPrefix("{") ? "subagent" : source),
                project: (row[5] as? String).map { URL(fileURLWithPath: $0).lastPathComponent },
                status: codexStatus(turn),
                updatedAt: Date(timeIntervalSince1970: Double(row[4] as? Int64 ?? 0)),
                tokens: (row[3] as? Int64).map(Int.init),
                model: row[2] as? String
            )
        }
    }

    static func codexStatus(_ turn: String?) -> AgentSession.Status {
        switch turn {
        case "inProgress": return .running
        case "completed": return .finished
        case "interrupted": return .interrupted
        case "failed": return .failed
        case nil: return .unknown("sin tareas")
        case let other?: return .unknown(other)
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Lectura minima de SQLite en solo lectura. Si la base esta bloqueada por la app
/// que la escribe, se abre como inmutable (puede faltar lo ultimo del WAL).
enum SQLiteReader {
    static func rows(at url: URL, sql: String, bind: [String] = []) -> [[Any?]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        for mode in ["ro", "ro&immutable=1"] {
            var db: OpaquePointer?
            let uri = "file:\(url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)?mode=\(mode)"
            guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
                sqlite3_close(db)
                continue
            }
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (index, value) in bind.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
            }
            var result: [[Any?]] = []
            var code = sqlite3_step(statement)
            while code == SQLITE_ROW {
                result.append((0..<sqlite3_column_count(statement)).map { column -> Any? in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: return sqlite3_column_int64(statement, column)
                    case SQLITE_FLOAT: return sqlite3_column_double(statement, column)
                    case SQLITE_TEXT: return sqlite3_column_text(statement, column).map { String(cString: $0) }
                    default: return nil
                    }
                })
                code = sqlite3_step(statement)
            }
            if code == SQLITE_DONE { return result }
        }
        return []
    }
}
