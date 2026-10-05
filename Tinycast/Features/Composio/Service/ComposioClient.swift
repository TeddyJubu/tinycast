import Foundation

/// Composio's REST API on a private session. A redirect onto another host is refused.
final class ComposioClient: Sendable {
    let apiKey: String
    private let session: URLSession
    private let redirectGuard: RedirectGuard

    init(apiKey: String) {
        self.apiKey = apiKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        let redirectGuard = RedirectGuard()
        self.redirectGuard = redirectGuard
        session = URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func toolkits(search: String) async throws -> [ComposioToolkit] {
        guard let url = ComposioAPI.toolkitsURL(search: search) else {
            throw ComposioAPI.Failure(message: "The app catalog could not be requested.")
        }
        return try ComposioAPI.toolkits(from: try await data(for: request(url: url)))
    }

    func createSession(userID: String, toolkitSlug: String) async throws -> ComposioSessionEndpoint {
        var request = request(url: ComposioAPI.sessionURL(), method: "POST")
        request.httpBody = try ComposioAPI.sessionBody(userID: userID, toolkitSlug: toolkitSlug)
        return try ComposioAPI.session(from: try await data(for: request))
    }

    func connectLink(sessionID: String, toolkitSlug: String) async throws -> URL {
        var request = request(url: ComposioAPI.linkURL(sessionID: sessionID), method: "POST")
        request.httpBody = try ComposioAPI.linkBody(toolkitSlug: toolkitSlug)
        return try ComposioAPI.connectLink(from: try await data(for: request))
    }

    func activeSlugs(userID: String) async throws -> Set<String> {
        guard let url = ComposioAPI.accountsURL(userID: userID) else {
            throw ComposioAPI.Failure(message: "Connected apps could not be requested.")
        }
        return try ComposioAPI.activeSlugs(from: try await data(for: request(url: url)))
    }

    func registerMCPServer(
        slug: String, name: String, appURL: String, auth: ComposioMCPAuth, discoveryURL: String?
    ) async throws -> String {
        var request = request(url: ComposioAPI.baseURL.appending(path: "custom/toolkits/upsert"), method: "POST")
        request.httpBody = try ComposioAPI.customToolkitBody(
            slug: slug, name: name, appURL: appURL, auth: auth, discoveryURL: discoveryURL)
        return try ComposioAPI.customSlug(from: try await data(for: request))
    }

    func syncMCPServer(slug: String) async throws {
        var request = request(url: ComposioAPI.baseURL.appending(path: "custom/toolkits/sync"), method: "POST")
        request.httpBody = try ComposioAPI.syncBody(slug: slug)
        _ = try await data(for: request)
    }

    func deleteMCPServer(slug: String) async throws {
        let url = ComposioAPI.baseURL.appending(path: "custom/toolkits").appending(path: slug)
        _ = try await data(for: request(url: url, method: "DELETE"))
    }

    private func request(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ComposioAPI.Failure(message: "Composio could not be reached.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ComposioAPI.Failure(message: "Composio did not answer.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ComposioAPI.Failure(message: ComposioAPI.message(from: data, status: http.statusCode))
        }
        return data
    }
}

/// Stateless: a redirected request keeps the API key only when the host does not change.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession, task: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard task.originalRequest?.url?.host?.lowercased() == request.url?.host?.lowercased() else {
            return nil
        }
        return request
    }
}
