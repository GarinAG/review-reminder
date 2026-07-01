import Foundation

struct GitLabUser: Codable, Sendable, Equatable {
    let id: Int
    let username: String
    let name: String
    let email: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name, email
        case avatarURL = "avatar_url"
    }
}

struct GitLabMR: Codable, Sendable {
    let id: Int
    let iid: Int
    let projectId: Int
    let title: String
    let webURL: String
    let state: String
    let hasConflicts: Bool
    let updatedAt: Date
    let createdAt: Date
    let sha: String?
    let author: GitLabUser
    let draft: Bool
    let workInProgress: Bool
    let labels: [String]

    var isDraft: Bool { draft || workInProgress }

    enum CodingKeys: String, CodingKey {
        case id, iid, title, state, sha, author, draft, labels
        case projectId     = "project_id"
        case webURL        = "web_url"
        case hasConflicts  = "has_conflicts"
        case updatedAt     = "updated_at"
        case createdAt     = "created_at"
        case workInProgress = "work_in_progress"
    }
}

struct GitLabApprovals: Sendable {
    let approvalsRequired: Int
    let approvedBy: [ApprovalEntry]
}

extension GitLabApprovals: Decodable {
    enum CodingKeys: String, CodingKey {
        case approvalsRequired = "approvals_required"
        case approvedBy        = "approved_by"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // approvals_required absent on some GitLab CE configurations
        approvalsRequired = (try? c.decodeIfPresent(Int.self, forKey: .approvalsRequired)) ?? 0
        approvedBy        = (try? c.decode([ApprovalEntry].self, forKey: .approvedBy)) ?? []
    }
}

struct ApprovalEntry: Codable, Sendable {
    let user: GitLabUser
}

struct GitLabProject: Codable, Sendable {
    let id: Int
    let pathWithNamespace: String
    let webURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case pathWithNamespace = "path_with_namespace"
        case webURL = "web_url"
    }
}

struct GitLabDiscussionNote: Codable, Sendable {
    let resolvable: Bool?
    let resolved: Bool?
}

struct GitLabDiscussion: Codable, Sendable {
    let id: String
    let individualNote: Bool
    let notes: [GitLabDiscussionNote]

    enum CodingKeys: String, CodingKey {
        case id, notes
        case individualNote = "individual_note"
    }

    var isResolvable: Bool { notes.first?.resolvable == true }
    var isResolved: Bool { notes.first?.resolvable == true && notes.first?.resolved == true }
}

struct GitLabNote: Codable, Sendable {
    let id: Int
    let body: String
    let author: GitLabUser
    let system: Bool

    enum CodingKeys: String, CodingKey {
        case id, body, author, system
    }
}
