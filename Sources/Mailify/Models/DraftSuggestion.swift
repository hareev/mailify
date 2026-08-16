import Foundation

enum DraftSuggestionStatus: String, Codable {
    case pending
    case accepted
    case dismissed
}

struct DraftSuggestion: Codable, Identifiable, Equatable {
    let id: UUID
    var emailMessageID: String
    var suggestedSubject: String
    var suggestedBody: String
    var reasoning: String?
    var status: DraftSuggestionStatus
    var createdAt: Date
    var decidedAt: Date?
    var gmailDraftID: String? // populated on accept

    init(id: UUID = UUID(), emailMessageID: String, suggestedSubject: String, suggestedBody: String,
         reasoning: String? = nil, status: DraftSuggestionStatus = .pending, createdAt: Date = Date(),
         decidedAt: Date? = nil, gmailDraftID: String? = nil) {
        self.id = id
        self.emailMessageID = emailMessageID
        self.suggestedSubject = suggestedSubject
        self.suggestedBody = suggestedBody
        self.reasoning = reasoning
        self.status = status
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.gmailDraftID = gmailDraftID
    }
}
