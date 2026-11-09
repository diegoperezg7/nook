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
    private(set) var sessions: [AgentSession] = []
    private(set) var claudeUsage: SubscriptionUsage?
    /// Codex expone el consumo solo por su app-server: pendiente de decidir (fase 2).
    let codexUsage: SubscriptionUsage? = nil

    /// Herramientas que se estan usando: con una sesion en curso o pendiente, o con
    /// actividad en la ultima media hora. Si no hay ninguna, la ultima usada.
    var activeFamilies: [AgentSession.Family] {
        AgentSources.activeFamilies(in: sessions)
    }

    func usage(for family: AgentSession.Family) -> SubscriptionUsage? {
        family == .claude ? claudeUsage : codexUsage
    }

    @ObservationIgnored private let home: URL
    @ObservationIgnored private var refreshing = false

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
        sessions = snapshot.0.sorted { $0.updatedAt > $1.updatedAt }
        claudeUsage = snapshot.1
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
}

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
            model: nil
        )
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
