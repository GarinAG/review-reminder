import Foundation

actor GitLabAPIClient {
    private let session: URLSession
    private var baseURL: String = ""
    private var token: String = ""
    private let throttle = RequestThrottle(limit: 5)

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = fmt.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid date: \(str)"
            )
        }
        return d
    }()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func configure(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        self.token = token
    }

    func fetchCurrentUser() async throws -> GitLabUser {
        try await get("/api/v4/user")
    }

    func fetchProject(path: String) async throws -> GitLabProject {
        var chars = CharacterSet.urlPathAllowed
        chars.remove(charactersIn: "/")
        let encoded = path.addingPercentEncoding(withAllowedCharacters: chars) ?? path
        return try await get("/api/v4/projects/\(encoded)")
    }

    func fetchOpenMRs(projectId: Int) async throws -> [GitLabMR] {
        var all: [GitLabMR] = []
        var page = 1
        while true {
            let batch: [GitLabMR] = try await get(
                "/api/v4/projects/\(projectId)/merge_requests",
                query: ["state": "opened", "per_page": "100", "page": "\(page)",
                        "with_merge_status_recheck": "true"]
            )
            all += batch
            if batch.count < 100 { break }
            page += 1
        }
        return all
    }

    func fetchApprovals(projectId: Int, mrIid: Int) async throws -> GitLabApprovals {
        try await get("/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/approvals")
    }

    func approveMR(projectId: Int, mrIid: Int) async throws {
        try await post("/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/approve")
    }

    func fetchUserProjects() async throws -> [GitLabProject] {
        var all: [GitLabProject] = []
        var page = 1
        while true {
            let batch: [GitLabProject] = try await get(
                "/api/v4/projects",
                query: ["membership": "true", "simple": "true",
                        "order_by": "last_activity_at", "per_page": "100", "page": "\(page)"]
            )
            all += batch
            if batch.count < 100 { break }
            page += 1
        }
        return all
    }

    func fetchMRByPath(projectPath: String, mrIid: Int) async throws -> GitLabMR {
        var chars = CharacterSet.urlPathAllowed
        chars.remove(charactersIn: "/")
        let encoded = projectPath.addingPercentEncoding(withAllowedCharacters: chars) ?? projectPath
        return try await get("/api/v4/projects/\(encoded)/merge_requests/\(mrIid)")
    }

    func fetchNotes(projectId: Int, mrIid: Int) async throws -> [GitLabNote] {
        try await get(
            "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/notes",
            query: ["sort": "asc", "order_by": "created_at", "per_page": "100"]
        )
    }

    func fetchDiscussions(projectId: Int, mrIid: Int) async throws -> [GitLabDiscussion] {
        try await get(
            "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/discussions",
            query: ["per_page": "100"]
        )
    }

    // MARK: - Private

    private func get<T: Decodable>(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> T {
        var components = URLComponents(string: baseURL + path)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw APIError.invalidURL(baseURL + path)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await performWithRetry(request)
        return try decoder.decode(T.self, from: data)
    }

    private func post(_ path: String) async throws {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL(baseURL + path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await performWithRetry(request)
    }

    // Retries 429/5xx with exponential backoff; other HTTP errors fail immediately.
    private func performWithRetry(_ request: URLRequest, maxAttempts: Int = 3) async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1
            await throttle.acquire()
            let result: Result<(Data, URLResponse), Error>
            do {
                result = .success(try await session.data(for: request))
            } catch {
                result = .failure(error)
            }
            await throttle.release()

            switch result {
            case .failure(let error):
                if attempt >= maxAttempts { throw error }
            case .success(let (data, response)):
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                if (200..<300).contains(http.statusCode) {
                    return data
                }
                let retryable = http.statusCode == 429 || (500..<600).contains(http.statusCode)
                let body = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
                if !retryable || attempt >= maxAttempts {
                    throw APIError.httpError(http.statusCode, body)
                }
            }

            let delaySeconds = pow(2.0, Double(attempt - 1))
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
    }
}

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u):       "Invalid URL: \(u)"
        case .invalidResponse:         "Invalid server response"
        case .httpError(let c, let m): "HTTP \(c): \(m)"
        }
    }
}
