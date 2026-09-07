import Foundation

struct SupabaseConfiguration: Sendable {
    let url: URL
    let anonymousKey: String

    /// Resolves the values that `Configuration.xcconfig` substitutes into `Round-Info.plist`.
    /// That xcconfig is gitignored, so a populated one is invisible to search while still being
    /// present in the build; only the `YOUR_`-placeholder template is searchable. Read the file
    /// before concluding a checkout is unconfigured. Returning nil routes `AppEnvironment` to
    /// `DemoAppRepository` and leaves `authService` nil, which disables email sign-in.
    static var bundled: SupabaseConfiguration? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: rawURL),
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty,
              !rawURL.contains("YOUR_") else { return nil }
        return .init(url: url, anonymousKey: key)
    }
}

struct SupabaseClient: Sendable {
    let configuration: SupabaseConfiguration
    let keychain: KeychainStore
    var session: URLSession = .shared

    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        requiresSession: Bool = true,
        extraHeaders: [String: String] = [:],
        allowRefresh: Bool = true,
        clockSkewAttempt: Int = 0
    ) async throws -> Data {
        var request = URLRequest(url: try endpoint(for: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonymousKey, forHTTPHeaderField: "apikey")
        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        if requiresSession {
            guard let token = keychain.value(for: "accessToken") else { throw RepositoryError.authenticationRequired }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if request.value(forHTTPHeaderField: "Authorization") == nil {
            request.setValue("Bearer \(configuration.anonymousKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RepositoryError.server("Invalid server response.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(in: data)

            // A token can be a fraction of a second "newer" than the clock of the service
            // validating it, which rejects it outright. The window closes on its own, so wait
            // for the receiving clock to catch up rather than surfacing a load failure.
            if let message, Self.indicatesUnsyncedClock(message), clockSkewAttempt < Self.clockSkewRetryDelays.count {
                try await Task.sleep(for: Self.clockSkewRetryDelays[clockSkewAttempt])
                return try await self.request(
                    path: path,
                    method: method,
                    body: body,
                    requiresSession: requiresSession,
                    extraHeaders: extraHeaders,
                    allowRefresh: allowRefresh,
                    clockSkewAttempt: clockSkewAttempt + 1
                )
            }
            if http.statusCode == 401, requiresSession, allowRefresh {
                try await refreshSession()
                return try await self.request(
                    path: path,
                    method: method,
                    body: body,
                    requiresSession: requiresSession,
                    extraHeaders: extraHeaders,
                    allowRefresh: false,
                    clockSkewAttempt: clockSkewAttempt
                )
            }
            if http.statusCode == 401 { throw RepositoryError.authenticationRequired }
            throw RepositoryError.server(message ?? "The server returned \(http.statusCode).")
        }
        return data
    }

    private static let clockSkewRetryDelays: [Duration] = [.milliseconds(400), .milliseconds(900), .milliseconds(1_600)]

    static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["message"] as? String
            ?? json["error_description"] as? String
            ?? json["msg"] as? String
            ?? json["error"] as? String
    }

    static func indicatesUnsyncedClock(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("issued at future") || normalized.contains("issued in the future")
    }

    /// Builds a request URL from a `/path?query` string. `URL.appending(path:)` percent-encodes
    /// the whole argument, which turns `?` into `%3F` and makes Supabase answer 404.
    func endpoint(for path: String) throws -> URL {
        guard var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false) else {
            throw RepositoryError.server("Invalid Supabase URL.")
        }
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let suffix = parts[0].hasPrefix("/") ? String(parts[0]) : "/\(parts[0])"
        components.path = basePath + suffix
        components.percentEncodedQuery = parts.count > 1 ? String(parts[1]) : nil
        guard let url = components.url else { throw RepositoryError.server("Invalid Supabase URL.") }
        return url
    }

    func rpc(_ functionName: String, parameters: [String: Any] = [:]) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: parameters)
        return try await request(path: "/rest/v1/rpc/\(functionName)", method: "POST", body: body)
    }

    func rpcVoid(_ functionName: String, parameters: [String: Any] = [:]) async throws {
        _ = try await rpc(functionName, parameters: parameters)
    }

    func upload(to uploadURL: URL, data: Data, contentType: String = "video/quicktime") async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonymousKey, forHTTPHeaderField: "apikey")
        if let token = keychain.value(for: "accessToken") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RepositoryError.server("Clip upload failed.")
        }
    }

    func storeSession(from data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw RepositoryError.server("Supabase did not return a valid session.")
        }
        try keychain.set(accessToken, for: "accessToken")
        try keychain.set(refreshToken, for: "refreshToken")
        if let user = json["user"] as? [String: Any], let id = user["id"] as? String {
            try keychain.set(id, for: "userID")
        }
    }

    private func refreshSession() async throws {
        guard let refreshToken = keychain.value(for: "refreshToken") else {
            throw RepositoryError.authenticationRequired
        }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let data = try await request(
            path: "/auth/v1/token?grant_type=refresh_token",
            method: "POST",
            body: body,
            requiresSession: false,
            allowRefresh: false
        )
        try storeSession(from: data)
    }
}

struct SupabaseAuthService: Sendable {
    private let client: SupabaseClient
    private let keychain: KeychainStore

    init(configuration: SupabaseConfiguration, keychain: KeychainStore) {
        self.keychain = keychain
        client = SupabaseClient(configuration: configuration, keychain: keychain)
    }

    func exchangeAppleIdentityToken(_ token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": token
        ])
        let data = try await client.request(
            path: "/auth/v1/token?grant_type=id_token",
            method: "POST",
            body: body,
            requiresSession: false
        )
        try client.storeSession(from: data)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "data": [
                "display_name": displayName,
                "timezone": TimeZone.current.identifier
            ]
        ])
        let data = try await client.request(
            path: "/auth/v1/signup",
            method: "POST",
            body: body,
            requiresSession: false
        )
        // Some projects require email confirmation and return no session.
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["access_token"] is String {
            try client.storeSession(from: data)
            return
        }
        // Fall through to password sign-in when confirmation is disabled / auto-confirmed.
        try await signIn(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])
        let data = try await client.request(
            path: "/auth/v1/token?grant_type=password",
            method: "POST",
            body: body,
            requiresSession: false
        )
        try client.storeSession(from: data)
    }

    func signOut() { keychain.removeAll() }
}
