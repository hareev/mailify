import Foundation

enum CategorySuggestionStatus: String, Codable {
    case pending
    case accepted
    case dismissed
}

/// An AI-proposed *new* category, pending user review — never auto-created.
/// `sourceMessageIDs` accumulates every message that independently
/// triggered/reinforced the same proposed name (see `decide`'s `.mergeInto`).
struct CategorySuggestion: Codable, Identifiable, Equatable {
    let id: UUID
    var proposedName: String
    var proposedColorHex: String
    var reasoning: String?
    var sourceMessageIDs: [String]
    var status: CategorySuggestionStatus
    var createdAt: Date
    var decidedAt: Date?

    init(id: UUID = UUID(), proposedName: String, proposedColorHex: String, reasoning: String? = nil,
         sourceMessageIDs: [String], status: CategorySuggestionStatus = .pending, createdAt: Date = Date(),
         decidedAt: Date? = nil) {
        self.id = id
        self.proposedName = proposedName
        self.proposedColorHex = proposedColorHex
        self.reasoning = reasoning
        self.sourceMessageIDs = sourceMessageIDs
        self.status = status
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }
}

extension CategorySuggestion {
    enum Decision: Equatable {
        case ignore
        case mergeInto(UUID)
        case create(name: String, colorHex: String)
    }

    /// Pure decision logic for whether/how to record a proposed new category,
    /// given a categorization result and current store state. No side
    /// effects, no AppStore/mutateStore dependency — unit-testable via
    /// run-eval.sh (see Eval/main.swift section 5).
    static func decide(
        classifiedCategoryName: String,
        proposedRawName: String?,
        existingCategories: [Category],
        existingSuggestions: [CategorySuggestion]
    ) -> Decision {
        // Defensive server-side enforcement of the system-prompt instruction
        // ("only propose when classifying as Other") — forced tool-use makes
        // the *shape* of Claude's response reliable, not that it follows
        // prose instructions within that shape. Without this guard, Claude
        // could set category_name: "Job" and also fill in a proposed name,
        // and accepting it would silently pull a correctly-classified
        // message into an unrelated new category.
        guard classifiedCategoryName == Category.otherName, let raw = proposedRawName else { return .ignore }

        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .ignore }

        // Never duplicate an existing category name (case-insensitive).
        guard !existingCategories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return .ignore
        }

        if let match = existingSuggestions.first(where: {
            $0.status == .pending && $0.proposedName.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return .mergeInto(match.id)
        }

        let usedHexes = existingCategories.map(\.colorHex)
            + existingSuggestions.filter { $0.status == .pending }.map(\.proposedColorHex)
        return .create(name: name, colorHex: Category.nextSuggestionColor(avoiding: usedHexes))
    }
}
