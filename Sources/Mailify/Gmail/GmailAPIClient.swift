import Foundation

/// Plain URLSession/Codable wrapper around the Gmail REST API. Handles access-token
/// refresh transparently via GmailOAuthManager + KeychainStore before every call.
final class GmailAPIClient {
    private let account: Account
    private let oauth: GmailOAuthManager

    init(account: Account, oauth: GmailOAuthManager) {
        self.account = account
        self.oauth = oauth
    }

    enum APIError: LocalizedError {
        case notAuthenticated
        case http(Int, String)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Gmail account is not connected."
            case .http(let code, let body): return "Gmail API error \(code): \(body)"
            case .decoding(let err): return "Failed to decode Gmail response: \(err)"
            }
        }
    }

    private func validAccessToken() async throws -> String {
        let email = account.emailAddress
        let expiryString = KeychainStore.get(service: KeychainKeys.gmailExpiryService(email: email), account: KeychainKeys.gmailAccount)
        let expiresAt = expiryString.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }

        if let accessToken = KeychainStore.get(service: KeychainKeys.gmailAccessTokenService(email: email), account: KeychainKeys.gmailAccount),
           let expiresAt, expiresAt.timeIntervalSinceNow > 60 {
            return accessToken
        }

        guard let refreshToken = KeychainStore.get(service: KeychainKeys.gmailRefreshTokenService(email: email), account: KeychainKeys.gmailAccount) else {
            throw APIError.notAuthenticated
        }

        let refreshed = try await oauth.refreshAccessToken(refreshToken: refreshToken)
        KeychainStore.set(refreshed.accessToken, service: KeychainKeys.gmailAccessTokenService(email: email), account: KeychainKeys.gmailAccount)
        KeychainStore.set(String(refreshed.expiresAt.timeIntervalSince1970), service: KeychainKeys.gmailExpiryService(email: email), account: KeychainKeys.gmailAccount)
        return refreshed.accessToken
    }

    private func authorizedRequest(_ url: URL, method: String = "GET") async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    func listMessageRefs(query: String, pageToken: String?) async throws -> GmailMessageListResponse {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: "50")]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = items

        let request = try await authorizedRequest(components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        do {
            return try JSONDecoder().decode(GmailMessageListResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func getMessage(id: String, format: String) async throws -> GmailMessage {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        var items = [URLQueryItem(name: "format", value: format)]
        if format == "metadata" {
            for header in ["From", "To", "Subject", "Date"] {
                items.append(URLQueryItem(name: "metadataHeaders", value: header))
            }
        }
        components.queryItems = items

        let request = try await authorizedRequest(components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        do {
            return try JSONDecoder().decode(GmailMessage.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func createDraft(rawMessage: String, threadId: String?) async throws -> String {
        var request = try await authorizedRequest(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts")!, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = GmailDraftCreateRequest(message: GmailDraftMessage(raw: rawMessage, threadId: threadId))
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        do {
            return try JSONDecoder().decode(GmailDraftCreateResponse.self, from: data).id
        } catch {
            throw APIError.decoding(error)
        }
    }

    private static func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
