import Foundation

// MARK: - users.messages.list

struct GmailMessageListResponse: Codable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageRef: Codable {
    let id: String
    let threadId: String
}

// MARK: - users.messages.get

struct GmailMessage: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: GmailMessagePart?
    let internalDate: String?
}

struct GmailMessagePart: Codable {
    let mimeType: String?
    let filename: String?
    let headers: [GmailHeader]?
    let body: GmailMessagePartBody?
    let parts: [GmailMessagePart]?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailMessagePartBody: Codable {
    let size: Int?
    let data: String? // base64url
}

// MARK: - users.drafts.create

struct GmailDraftCreateRequest: Codable {
    let message: GmailDraftMessage
}

struct GmailDraftMessage: Codable {
    let raw: String
    let threadId: String?
}

struct GmailDraftCreateResponse: Codable {
    let id: String
}

// MARK: - OAuth token responses

struct GoogleTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}
