import Foundation

enum ActionItemStatus: String, Codable {
    case pending
    case done
    case dismissed
}

/// An AI-detected action the user needs to take on an email — distinct from
/// a DraftSuggestion (which proposes a reply). Surfaces things like "ACTION
/// NEEDED by 8/19: sign the consent form" up front instead of leaving them
/// buried in the inbox, per CLAUDE.md's first pillar ("surface what actually
/// needs action, up front"). Local-only tracking: no calendar/reminders
/// integration, just a reviewable queue mirroring DraftSuggestion/
/// CategorySuggestion's accept-or-dismiss pattern.
struct ActionItem: Codable, Identifiable, Equatable {
    let id: UUID
    var emailMessageID: String
    var summary: String
    var dueDate: Date?
    var status: ActionItemStatus
    var createdAt: Date
    var decidedAt: Date?

    init(id: UUID = UUID(), emailMessageID: String, summary: String, dueDate: Date? = nil,
         status: ActionItemStatus = .pending, createdAt: Date = Date(), decidedAt: Date? = nil) {
        self.id = id
        self.emailMessageID = emailMessageID
        self.summary = summary
        self.dueDate = dueDate
        self.status = status
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }
}
