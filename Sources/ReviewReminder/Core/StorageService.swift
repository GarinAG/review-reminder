import Foundation
import GRDB

actor StorageService {
    private var db: DatabaseQueue?

    func setup() throws {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ReviewReminder", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbPath = dir.appendingPathComponent("reviewer.sqlite").path
        let queue = try DatabaseQueue(path: dbPath)
        try migrate(queue)
        self.db = queue
    }

    // MARK: - MR Records

    func upsertMR(_ mr: MRRecord) throws -> Int64 {
        guard let db else { throw StorageError.notSetup }
        return try db.write { conn in
            var record = mr
            if let existing = try MRRecord
                .filter(Column("gitlabId") == mr.gitlabId && Column("projectPath") == mr.projectPath)
                .fetchOne(conn) {
                record.id = existing.id
                try record.update(conn)
                return existing.id!
            } else {
                try record.insert(conn)
                return record.id!
            }
        }
    }

    func fetchMRRecord(gitlabId: Int, projectPath: String) throws -> MRRecord? {
        guard let db else { throw StorageError.notSetup }
        return try db.read { conn in
            try MRRecord
                .filter(Column("gitlabId") == gitlabId && Column("projectPath") == projectPath)
                .fetchOne(conn)
        }
    }

    func allMRRecords() throws -> [MRRecord] {
        guard let db else { throw StorageError.notSetup }
        return try db.read { conn in try MRRecord.fetchAll(conn) }
    }

    func deleteMRsNotIn(gitlabIds: Set<Int>, projectPath: String) throws {
        guard let db else { throw StorageError.notSetup }
        try db.write { conn in
            try MRRecord
                .filter(Column("projectPath") == projectPath)
                .filter(!gitlabIds.contains(Column("gitlabId")))
                .deleteAll(conn)
        }
    }

    func updateLastSeenNoteId(mrId: Int64, noteId: Int) throws {
        guard let db else { throw StorageError.notSetup }
        try db.write { conn in
            try conn.execute(
                sql: "UPDATE merge_requests SET lastSeenNoteId = ? WHERE id = ?",
                arguments: [noteId, mrId]
            )
        }
    }

    // MARK: - User States

    func upsertUserState(_ state: MRUserStateRecord) throws {
        guard let db else { throw StorageError.notSetup }
        try db.write { conn in try state.save(conn) }
    }

    func userState(for mrId: Int64) throws -> MRUserStateRecord? {
        guard let db else { throw StorageError.notSetup }
        return try db.read { conn in
            try MRUserStateRecord.fetchOne(conn, key: mrId)
        }
    }

    func allUserStates() throws -> [MRUserStateRecord] {
        guard let db else { throw StorageError.notSetup }
        return try db.read { conn in try MRUserStateRecord.fetchAll(conn) }
    }

    func resetExpiredSnoozes() throws {
        guard let db else { throw StorageError.notSetup }
        try db.write { conn in
            try MRUserStateRecord
                .filter(Column("status") == MRStatus.snoozed.rawValue)
                .filter(Column("snoozedUntil") < Date())
                .updateAll(conn, Column("status").set(to: MRStatus.pending.rawValue))
        }
    }

    // MARK: - Events

    func hasEvent(_ type: ReviewEventType, mrId: Int64) throws -> Bool {
        guard let db else { throw StorageError.notSetup }
        return try db.read { conn in
            try ReviewEventRecord
                .filter(Column("mrId") == mrId)
                .filter(Column("eventType") == type.rawValue)
                .fetchCount(conn) > 0
        }
    }

    func recordEvent(_ event: ReviewEventRecord) throws {
        guard let db else { throw StorageError.notSetup }
        try db.write { conn in
            var e = event
            try e.insert(conn)
        }
    }

    func deleteAllEvents() throws {
        guard let db else { throw StorageError.notSetup }
        _ = try db.write { conn in
            try ReviewEventRecord.deleteAll(conn)
        }
    }

    // MARK: - Stats

    func fetchStats() throws -> ReviewStats {
        guard let db else { throw StorageError.notSetup }
        return try db.read { conn in
            let total = try ReviewEventRecord
                .filter(Column("eventType") == ReviewEventType.reviewed.rawValue)
                .fetchCount(conn)

            let approved = try ReviewEventRecord
                .filter(Column("eventType") == ReviewEventType.approved.rawValue)
                .fetchCount(conn)

            let snoozed = try ReviewEventRecord
                .filter(Column("eventType") == ReviewEventType.snoozed.rawValue)
                .fetchCount(conn)

            let ignored = try ReviewEventRecord
                .filter(Column("eventType") == ReviewEventType.ignored.rawValue)
                .fetchCount(conn)

            let recentEvents = try ReviewEventRecord
                .order(Column("occurredAt").desc)
                .limit(200)
                .fetchAll(conn)

            return ReviewStats(
                totalReviewed: total,
                totalApproved: approved,
                totalSnoozed: snoozed,
                totalIgnored: ignored,
                recentEvents: recentEvents
            )
        }
    }

    // MARK: - Migration

    private func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "merge_requests", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gitlabId", .integer).notNull()
                t.column("projectPath", .text).notNull()
                t.column("title", .text).notNull()
                t.column("url", .text).notNull()
                t.column("authorUsername", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("lastCommitSha", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["gitlabId", "projectPath"])
            }

            try db.create(table: "mr_user_states", ifNotExists: true) { t in
                t.column("mrId", .integer).primaryKey().references("merge_requests", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("snoozedUntil", .datetime)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "review_events", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("mrId", .integer).notNull().references("merge_requests", onDelete: .cascade)
                t.column("eventType", .text).notNull()
                t.column("occurredAt", .datetime).notNull()
                t.column("extraJSON", .text)
            }

            try db.create(indexOn: "merge_requests", columns: ["gitlabId", "projectPath"])
            try db.create(indexOn: "review_events", columns: ["mrId"])
            try db.create(indexOn: "review_events", columns: ["occurredAt"])
        }

        migrator.registerMigration("v2_approvals_and_notes") { db in
            try db.alter(table: "merge_requests") { t in
                t.add(column: "mrIid", .integer).notNull().defaults(to: 0)
                t.add(column: "projectId", .integer).notNull().defaults(to: 0)
                t.add(column: "approvalsCount", .integer).notNull().defaults(to: 0)
                t.add(column: "approvalsRequired", .integer).notNull().defaults(to: 1)
                t.add(column: "lastSeenNoteId", .integer).notNull().defaults(to: 0)
            }
        }

        // Remove FK cascade from review_events so events survive MR record deletion
        migrator.registerMigration("v3_events_no_cascade") { db in
            try db.execute(sql: """
                CREATE TABLE review_events_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    mrId INTEGER NOT NULL,
                    eventType TEXT NOT NULL,
                    occurredAt DATETIME NOT NULL,
                    extraJSON TEXT
                )
                """)
            try db.execute(sql: "INSERT INTO review_events_new SELECT * FROM review_events")
            try db.execute(sql: "DROP TABLE review_events")
            try db.execute(sql: "ALTER TABLE review_events_new RENAME TO review_events")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_events_mrId ON review_events(mrId)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_events_at ON review_events(occurredAt)")
        }

        try migrator.migrate(queue)
    }
}

struct ReviewStats: Sendable {
    let totalReviewed: Int
    let totalApproved: Int
    let totalSnoozed: Int
    let totalIgnored: Int
    let recentEvents: [ReviewEventRecord]
}

enum StorageError: LocalizedError {
    case notSetup

    var errorDescription: String? { "Storage not initialized" }
}
