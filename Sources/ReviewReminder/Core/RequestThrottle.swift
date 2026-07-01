import Foundation

// Bounds how many GitLab API calls are in flight at once, regardless of caller
// (polling across repos/MRs, stats fetching MR statuses, etc).
actor RequestThrottle {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        active += 1
    }

    func release() {
        active -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
