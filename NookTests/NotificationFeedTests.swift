import SQLite3
import XCTest
@testable import Nook

/// Lectura de la base de notificaciones con una copia de su formato.
final class NotificationFeedTests: XCTestCase {
    private var path: String!

    override func setUpWithError() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("notif-\(UUID().uuidString).db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR); CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB);", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO app VALUES (1, 'com.apple.mail');", nil, nil, nil)
        try insert(db, 1, ["app": "com.apple.mail", "req": ["titl": "Ana", "body": "Te envío el presupuesto"]])
        sqlite3_close(db)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func insert(_ db: OpaquePointer?, _ id: Int64, _ plist: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO record (rec_id, app_id, data) VALUES (?, 1, ?)", -1, &statement, nil)
        sqlite3_bind_int64(statement, 1, id)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
    }

    func testFirstReadOnlyMarksThePosition() {
        guard case let .rows(maxID, notices) = NotificationFeed.read(after: nil, path: path) else { return XCTFail() }
        XCTAssertEqual(maxID, 1)
        XCTAssertTrue(notices.isEmpty, "no se repiten las notificaciones antiguas")
    }

    func testNewNotificationsAreRead() throws {
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        try insert(db, 2, ["app": "com.apple.mail", "req": ["titl": "Luis", "subt": "Reunión", "body": "¿Movemos a las 5?"]])
        try insert(db, 3, ["app": "com.apple.mail", "req": [String: Any]()])
        sqlite3_close(db)
        guard case let .rows(maxID, notices) = NotificationFeed.read(after: 1, path: path) else { return XCTFail() }
        XCTAssertEqual(maxID, 3)
        XCTAssertEqual(notices, [.init(bundleID: "com.apple.mail", title: "Luis", body: "¿Movemos a las 5?")], "las vacias no salen")
    }

    func testMissingDatabaseIsDenied() {
        guard case .denied = NotificationFeed.read(after: 1, path: "/no/existe/db") else { return XCTFail() }
    }
}
