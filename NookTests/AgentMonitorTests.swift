import SQLite3
import XCTest
@testable import Nook

/// Cada fuente de la pestaña de agentes con datos simulados en una carpeta personal
/// de prueba: lo que llega al panel es lo que dan los archivos, y nada mas.
final class AgentMonitorTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func writeSession(pid: Int, _ fields: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: fields)
        try data.write(to: home.appendingPathComponent(".claude/sessions/\(pid).json"))
    }

    // MARK: Claude Code

    func testClaudeSessionsFromTerminalAndVSCode() throws {
        try writeSession(pid: 1, [
            "pid": 1, "sessionId": "terminal", "cwd": "/Users/x/Proyectos/Nook", "entrypoint": "cli",
            "status": "busy", "statusUpdatedAt": 1_794_231_786_324, "name": "titulo privado",
        ])
        try writeSession(pid: 2, [
            "pid": 2, "sessionId": "vscode", "cwd": "/Users/x/web", "entrypoint": "claude-vscode",
            "status": "waiting", "waitingFor": "sandbox request", "statusUpdatedAt": 1_794_231_000_000,
        ])
        try writeSession(pid: 3, [
            "pid": 3, "sessionId": "hecha", "entrypoint": "cli", "status": "idle", "updatedAt": 1_794_200_000_000,
        ])

        let sessions = Dictionary(uniqueKeysWithValues: AgentSources.claudeSessions(home: home).map { ($0.id, $0) })
        let terminal = try XCTUnwrap(sessions["claude-terminal"])
        XCTAssertEqual(terminal.tool, .claudeTerminal)
        XCTAssertEqual(terminal.status, .running)
        XCTAssertEqual(terminal.project, "Nook")
        XCTAssertNil(terminal.tokens, "Claude Code no expone el consumo por sesion: no se inventa")

        let vscode = try XCTUnwrap(sessions["claude-vscode"])
        XCTAssertEqual(vscode.tool, .claudeVSCode)
        XCTAssertEqual(vscode.status, .pending("sandbox request"))

        XCTAssertEqual(sessions["claude-hecha"]?.status, .finished)
    }

    func testUnknownStatusIsShownAsUnknown() {
        let session = AgentSources.claudeSession(from: ["sessionId": "x", "entrypoint": "cli", "status": "nuevo"])
        XCTAssertEqual(session?.status, .unknown("nuevo"))
    }

    func testOnlyRunningOrWaitingSessionsAreActive() {
        XCTAssertTrue(AgentSession.Status.running.isActive)
        XCTAssertTrue(AgentSession.Status.pending("input needed").isActive)
        for stopped: AgentSession.Status in [.finished, .interrupted, .failed, .unknown("x")] {
            XCTAssertFalse(stopped.isActive, "\(stopped) no debe mostrarse")
        }
    }

    // MARK: Herramienta en uso

    private func session(_ tool: AgentSession.Tool, _ status: AgentSession.Status, minutesAgo: Double) -> AgentSession {
        AgentSession(id: UUID().uuidString, tool: tool, project: nil, status: status,
                     updatedAt: .now.addingTimeInterval(-minutesAgo * 60), tokens: nil, model: nil)
    }

    func testOnlyTheToolInUseIsShown() {
        let claudeBusy = session(.claudeTerminal, .running, minutesAgo: 120)
        let codexOld = session(.codex("vscode"), .finished, minutesAgo: 60 * 24 * 50)
        XCTAssertEqual(AgentSources.activeFamilies(in: [claudeBusy, codexOld]), [.claude])

        let codexNow = session(.codex("cli"), .finished, minutesAgo: 5)
        XCTAssertEqual(AgentSources.activeFamilies(in: [claudeBusy, codexNow]), [.claude, .codex])

        // Nada activo: la ultima usada.
        let claudeOld = session(.claudeVSCode, .finished, minutesAgo: 600)
        XCTAssertEqual(AgentSources.activeFamilies(in: [claudeOld, codexOld]), [.claude])
        XCTAssertEqual(AgentSources.activeFamilies(in: []), [])
    }

    // MARK: Consumo de Claude

    func testClaudeUsageSnapshot() throws {
        let url = home.appendingPathComponent(AgentMonitor.claudeUsageSnapshot)
        try Data("""
        {"updated_at":"2026-11-09T14:00:00.000Z",
         "five_hour":{"used_percentage":36,"resets_at":"2026-11-09T16:00:00.000Z"},
         "seven_day":{"used_percentage":54,"resets_at":"2026-11-12T11:00:00.000Z"}}
        """.utf8).write(to: url)

        let usage = try XCTUnwrap(AgentSources.claudeUsage(at: url))
        XCTAssertEqual(usage.windows.count, 2)
        XCTAssertEqual(usage.windows.map(\.usedPercent), [36, 54])
        XCTAssertNotNil(usage.windows.first?.resetsAt)
    }

    func testNoSnapshotMeansNoUsage() {
        XCTAssertNil(AgentSources.claudeUsage(at: home.appendingPathComponent(AgentMonitor.claudeUsageSnapshot)))
    }

    // MARK: Codex

    private func exec(_ db: OpaquePointer?, _ sql: String) {
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
    }

    func testCodexThreadsWithTheirLastTurn() throws {
        var state: OpaquePointer?
        sqlite3_open(home.appendingPathComponent(".codex/state_5.sqlite").path, &state)
        exec(state, """
        create table threads (id text primary key, source text, model text, tokens_used integer, updated_at integer,
            cwd text, archived integer, title text, first_user_message text);
        insert into threads values ('t1', 'vscode', 'gpt-5.6', 1200000, 1794200000, '/Users/x/MyFinancIA', 0, 'privado', 'privado');
        insert into threads values ('t2', 'cli', 'gpt-5.6', 3400, 1794100000, '/Users/x/web', 0, 'privado', 'privado');
        insert into threads values ('t3', 'cli', 'gpt-5.6', 10, 1794000000, '/Users/x/viejo', 1, 'privado', 'privado');
        """)
        sqlite3_close(state)

        var history: OpaquePointer?
        sqlite3_open(home.appendingPathComponent(".codex/thread_history_1.sqlite").path, &history)
        exec(history, """
        create table thread_turns (thread_id text, turn_id text, rollout_ordinal integer, status text);
        insert into thread_turns values ('t1', 'a', 1, 'completed');
        insert into thread_turns values ('t1', 'b', 2, 'inProgress');
        insert into thread_turns values ('t2', 'c', 1, 'completed');
        """)
        sqlite3_close(history)

        let threads = AgentSources.codexThreads(home: home)
        XCTAssertEqual(threads.map(\.id), ["codex-t1", "codex-t2"], "los archivados no salen")
        XCTAssertEqual(threads[0].status, .running, "manda la ultima tarea")
        XCTAssertEqual(threads[0].tokens, 1_200_000)
        XCTAssertEqual(threads[0].project, "MyFinancIA")
        XCTAssertEqual(threads[0].tool, .codex("vscode"))
        XCTAssertEqual(threads[1].status, .finished)
    }

    func testCodexStatusMapping() {
        XCTAssertEqual(AgentSources.codexStatus("interrupted"), .interrupted)
        XCTAssertEqual(AgentSources.codexStatus("failed"), .failed)
        XCTAssertEqual(AgentSources.codexStatus(nil), .unknown("sin tareas"))
    }

    func testMissingSourcesGiveNoSessions() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
        XCTAssertTrue(AgentSources.codexThreads(home: home).isEmpty)
        XCTAssertTrue(AgentSources.claudeSessions(home: home).isEmpty)
    }

    // MARK: Avisos

    private func status(_ id: String, _ status: AgentSession.Status) -> AgentSession {
        AgentSession(id: id, tool: .claudeTerminal, project: "nook", status: status,
                     updatedAt: .now, tokens: nil, model: nil)
    }

    func testFinishAndWaitingAreNotified() {
        let old = [status("a", .running), status("b", .running), status("c", .pending(nil)), status("d", .finished)]
        let new = [status("a", .finished), status("b", .pending("permiso")), status("c", .pending(nil)),
                   status("d", .running), status("e", .pending(nil))]
        let events = AgentSources.events(from: old, to: new)
        XCTAssertEqual(events.map(\.0.id), ["a", "b"])
        XCTAssertEqual(events.map(\.1), [.finished, .waiting])
    }

    func testPidIsRead() {
        let session = AgentSources.claudeSession(from: ["sessionId": "x", "status": "busy", "entrypoint": "cli", "pid": 4242])
        XCTAssertEqual(session?.pid, 4242)
    }
}
