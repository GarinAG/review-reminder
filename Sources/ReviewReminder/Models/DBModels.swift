import Foundation
import GRDB

struct MRRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "merge_requests"

    var id: Int64?
    let gitlabId: Int
    let projectPath: String
    let title: String
    let url: String
    let authorUsername: String
    var updatedAt: Date
    var lastCommitSha: String
    let createdAt: Date
    var mrIid: Int
    var projectId: Int
    var approvalsCount: Int
    var approvalsRequired: Int
    var lastSeenNoteId: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct MRUserStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "mr_user_states"

    let mrId: Int64
    var status: MRStatus
    var snoozedUntil: Date?
    var updatedAt: Date
}

struct MREventMeta: Codable, Sendable {
    let title: String
    let url: String?
    var mrIid: Int?
    var projectPath: String?
}

struct ReviewEventRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "review_events"

    var id: Int64?
    let mrId: Int64
    let eventType: ReviewEventType
    let occurredAt: Date
    var extraJSON: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var meta: MREventMeta? {
        guard let json = extraJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MREventMeta.self, from: data)
    }

    static func metaJSON(title: String, url: String?, mrIid: Int? = nil, projectPath: String? = nil) -> String? {
        guard let data = try? JSONEncoder().encode(MREventMeta(title: title, url: url, mrIid: mrIid, projectPath: projectPath)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum MRStatus: String, Codable, Sendable {
    case pending
    case snoozed
    case ignored
    case approved
}

enum ReviewEventType: String, Codable, Sendable, CaseIterable {
    case reviewed
    case approved
    case snoozed
    case ignored
    case changed
    case dismissed
}
