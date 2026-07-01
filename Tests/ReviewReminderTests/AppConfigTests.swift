import Testing
@testable import ReviewReminder

struct AppConfigTests {
    @Test func defaultConfigIsNotConfigured() {
        let config = AppConfig()
        #expect(!config.isConfigured)
    }

    @Test func configuredWhenURLAndReposPresent() {
        var config = AppConfig()
        config.gitlabURL = "https://gitlab.example.com"
        config.repositories = ["group/repo"]
        #expect(config.isConfigured)
    }
}

struct MRDisplayItemTests {
    private func makeItem(status: MRStatus, snoozedUntil: Date? = nil) -> MRDisplayItem {
        MRDisplayItem(
            id: 1, gitlabId: 1, projectPath: "g/r", title: "Fix",
            url: URL(string: "https://example.com")!,
            author: "user", updatedAt: Date(), createdAt: Date(),
            status: status, snoozedUntil: snoozedUntil,
            mrIid: 1, projectId: 1, approvalsCount: 0, approvalsRequired: 1
        )
    }

    @Test func activeWhenPending() {
        #expect(makeItem(status: .pending).isActive)
    }

    @Test func notActiveWhenIgnored() {
        #expect(!makeItem(status: .ignored).isActive)
    }

    @Test func activeWhenSnoozedButExpired() {
        let item = makeItem(status: .snoozed, snoozedUntil: Date().addingTimeInterval(-60))
        #expect(item.isActive)
    }
}
