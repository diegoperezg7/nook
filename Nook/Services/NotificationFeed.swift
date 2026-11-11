import AppKit
import SQLite3

/// Notificaciones en el notch: lee las que macOS va entregando de su base de datos
/// (solo lectura) y avisa de las nuevas. Necesita Acceso total al disco; sin el, o si
/// macOS cambia el formato, no hace nada y Ajustes lo explica.
@MainActor
final class NotificationFeed {
    enum State: Equatable { case off, needsFullDiskAccess, unsupported, on }

    struct Notice: Equatable {
        let bundleID: String
        let title: String
        let body: String
    }

    private(set) var state: State = .off
    var onNotice: ((Notice) -> Void)?

    private var timer: Timer?
    private var lastID: Int64?
    private let queue = DispatchQueue(label: "com.diegoperez.nook.notifications")

    nonisolated static var databasePath: String {
        let home = getpwuid(getuid())?.pointee.pw_dir.map { String(cString: $0) } ?? NSHomeDirectory()
        return home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }

    func apply() {
        let enabled = UserDefaults.standard.bool(forKey: SettingsKey.notifications)
        if enabled, timer == nil {
            lastID = nil
            poll()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        } else if !enabled {
            timer?.invalidate()
            timer = nil
            state = .off
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func poll() {
        let since = lastID
        queue.async {
            let result = Self.read(after: since)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(result, firstRead: since == nil) }
            }
        }
    }

    private func apply(_ result: Result, firstRead: Bool) {
        switch result {
        case .denied: state = .needsFullDiskAccess
        case .unsupported: state = .unsupported
        case let .rows(maxID, notices):
            state = .on
            lastID = max(lastID ?? 0, maxID)
            // La primera lectura solo marca por donde va: no se repiten las antiguas.
            guard !firstRead else { return }
            let own = Bundle.main.bundleIdentifier
            for notice in notices where notice.bundleID != own { onNotice?(notice) }
        }
    }

    // MARK: - Base de datos

    enum Result { case denied, unsupported, rows(maxID: Int64, notices: [Notice]) }

    nonisolated static func read(after lastID: Int64?, path: String = databasePath) -> Result {
        // Sin Acceso total al disco ni siquiera se puede leer el archivo.
        guard FileManager.default.isReadableFile(atPath: path) else { return .denied }
        var db: OpaquePointer?
        let uri = "file:" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path) + "?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return .denied
        }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON a.app_id = r.app_id
        WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 20
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            // Sin permiso, la apertura funciona pero la primera consulta falla.
            let message = String(cString: sqlite3_errmsg(db))
            return message.contains("authorization") || message.contains("unable to open") ? .denied : .unsupported
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastID ?? Int64.max)
        var maxID: Int64 = lastID ?? 0
        var notices: [Notice] = []
        if lastID == nil {
            // Primera lectura: solo el ultimo id.
            var maxStatement: OpaquePointer?
            defer { sqlite3_finalize(maxStatement) }
            guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &maxStatement, nil) == SQLITE_OK,
                  sqlite3_step(maxStatement) == SQLITE_ROW else { return .unsupported }
            return .rows(maxID: sqlite3_column_int64(maxStatement, 0), notices: [])
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            maxID = max(maxID, id)
            guard let bundle = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
                  let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            if let notice = parse(data, bundleID: bundle) { notices.append(notice) }
        }
        return .rows(maxID: maxID, notices: notices)
    }

    /// El registro es un plist con `req` -> `titl`, `subt`, `body`.
    nonisolated static func parse(_ data: Data, bundleID: String) -> Notice? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }
        let title = (request["titl"] as? String) ?? ""
        let subtitle = (request["subt"] as? String) ?? ""
        let body = (request["body"] as? String) ?? ""
        let heading = title.isEmpty ? subtitle : title
        guard !heading.isEmpty || !body.isEmpty else { return nil }
        return Notice(bundleID: (plist["app"] as? String) ?? bundleID, title: heading, body: body)
    }

    #if DEBUG
    /// `-VisorDumpNotification <bundle id>`: estructura de la ultima notificacion de esa
    /// app (claves y tipos; los textos, enmascarados) para ver que datos trae.
    nonisolated static func dumpLatest(of bundleID: String, path: String = databasePath) -> String {
        var db: OpaquePointer?
        let uri = "file:" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path) + "?mode=ro"
        let folder = (path as NSString).deletingLastPathComponent
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: folder))?.joined(separator: ",") ?? "error: " + String(cString: strerror(errno))
        let root = ((folder as NSString).deletingLastPathComponent)
        var tree: [String] = []
        if let walker = FileManager.default.enumerator(atPath: root) {
            for case let item as String in walker where tree.count < 60 { tree.append(item) }
        }
        NSLog("VISORTREE %@: %@", root, tree.joined(separator: " | "))
        let probe = open(path, O_RDONLY)
        let detail = "carpeta [" + listing + "] abrir db: " + (probe >= 0 ? "ok" : String(cString: strerror(errno)))
        if probe >= 0 { close(probe) }
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return "sin acceso: " + detail }
        defer { sqlite3_close(db) }
        let sql = "SELECT r.data FROM record r JOIN app a ON a.app_id = r.app_id WHERE a.identifier = ? ORDER BY r.rec_id DESC LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return "consulta: " + String(cString: sqlite3_errmsg(db)) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bundleID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return "sin notificaciones de \(bundleID)" }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return "no es plist" }
        return describe(plist, indent: "")
    }

    /// Claves y tipos. Las cadenas, enmascaradas: letras como "a", cifras como "9",
    /// para ver la forma (un numero de telefono, un JID...) sin el contenido.
    nonisolated private static func describe(_ value: Any, indent: String) -> String {
        switch value {
        case let dict as [String: Any]:
            return dict.keys.sorted().map { key in "\(indent)\(key): " + describe(dict[key]!, indent: indent + "  ").trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n").prefixedNewline
        case let array as [Any]:
            return array.prefix(5).map { describe($0, indent: indent + "  ") }.joined(separator: "\n").prefixedNewline
        case let string as String:
            let masked = String(string.prefix(60).map { $0.isLetter ? "a" : $0.isNumber ? "9" : $0 })
            return "\"\(masked)\""
        case let data as Data:
            if let inner = try? PropertyListSerialization.propertyList(from: data, format: nil) {
                return "(plist)" + describe(inner, indent: indent + "  ")
            }
            return "<\(data.count) bytes>"
        default:
            return String(describing: type(of: value))
        }
    }

    /// Enmascara un texto: los identificadores de app (con puntos, sin espacios) se ven;
    /// el resto, letras como "a" y cifras como "9".
    nonisolated static func mask(_ text: String) -> String {
        let looksLikeID = text.contains(".") && !text.contains(" ") && text.count < 80
        if looksLikeID { return text }
        return String(text.prefix(50).map { $0.isLetter ? "a" : $0.isNumber ? "9" : $0 }) + (text.count > 50 ? "…(\(text.count))" : "")
    }

    /// `-VisorProbeBiome YES`: cadenas legibles del ultimo segmento de Biome de entregas.
    nonisolated static func probeBiome() -> String {
        let home = getpwuid(getuid())?.pointee.pw_dir.map { String(cString: $0) } ?? NSHomeDirectory()
        let folder = home + "/Library/Biome/streams/restricted/Notification.Delivery/local"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return "biome: sin acceso a \(folder)" }
        let sorted = files.compactMap { name -> (String, Date)? in
            let path = folder + "/" + name
            let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
            return date.map { (path, $0) }
        }.sorted { $0.1 > $1.1 }
        guard let latest = sorted.first, let data = FileManager.default.contents(atPath: latest.0) else { return "biome: vacio" }
        // Cadenas UTF-8 de 4+ caracteres imprimibles, las ultimas 60.
        var strings: [String] = [], current = [UInt8]()
        for byte in data {
            if byte >= 0x20 && byte < 0x7F || byte >= 0xC2 { current.append(byte) } else {
                if current.count >= 4, let text = String(bytes: current, encoding: .utf8) { strings.append(text) }
                current.removeAll()
            }
        }
        return "biome \(latest.0.split(separator: "/").last ?? "") (\(data.count) bytes):\n" + strings.suffix(60).map(mask).joined(separator: "\n")
    }
    #endif
}

#if DEBUG
private extension String {
    var prefixedNewline: String { isEmpty ? "{}" : "\n" + self }
}
#endif
