import Foundation

struct Category: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var isSystemDefault: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, colorHex: String, isSystemDefault: Bool = false, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isSystemDefault = isSystemDefault
        self.sortOrder = sortOrder
    }

    /// The "Other" category is the required fallback the classifier can always fall back to.
    static let otherName = "Other"

    static func seedDefaults() -> [Category] {
        let defs: [(String, String)] = [
            ("School", "#4FD1C5"),
            ("Investment", "#E8A33D"),
            ("Personal", "#A78BFA"),
            ("Job", "#60A5FA"),
            ("Shop", "#F472B6"),
            ("Purchase", "#34D399"),
            (otherName, "#9BA3B4")
        ]
        return defs.enumerated().map { index, def in
            Category(name: def.0, colorHex: def.1, isSystemDefault: true, sortOrder: index)
        }
    }

    /// Fixed palette for AI-proposed categories (see CategorySuggestion).
    /// Collision avoidance against existing categories/other pending
    /// suggestions happens at the call site via `nextSuggestionColor`.
    static let suggestionPalette: [String] = [
        "#F87171", "#FBBF24", "#34D399", "#38BDF8", "#818CF8", "#F472B6", "#A3E635", "#FB923C"
    ]

    static func nextSuggestionColor(avoiding usedHexes: [String]) -> String {
        let used = Set(usedHexes.map { $0.uppercased() })
        if let free = suggestionPalette.first(where: { !used.contains($0.uppercased()) }) {
            return free
        }
        // Palette exhausted (unlikely for a personal inbox's category count) — cycle.
        return suggestionPalette[usedHexes.count % suggestionPalette.count]
    }
}
