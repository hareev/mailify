import Foundation

/// The two AI "agents": categorization and draft-suggestion. Both use forced
/// tool-use so responses are structured/reliable rather than free-text to parse.
struct ClaudeAgentService {
    private let client = ClaudeAPIClient()

    struct CategorizationResult {
        let categoryName: String
        let confidence: Double
        let needsReply: Bool
        let reasoning: String?
        let proposedNewCategoryName: String?
        let proposedNewCategoryReasoning: String?
        let actionItemSummary: String?
        let actionDueDate: Date?
    }

    struct DraftResult {
        let subject: String
        let body: String
        let reasoning: String?
    }

    func categorize(email: EmailMessage, categories: [Category], apiKey: String) async throws -> CategorizationResult {
        let names = categories.map(\.name)
        let tool = ClaudeTool(
            name: "classify_email",
            description: "Classify an email into exactly one category and assess whether it needs a reply.",
            inputSchema: ClaudeJSONSchema(
                properties: [
                    "category_name": .init(type: "string", description: "Exactly one of the allowed categories.", enumValues: names),
                    "confidence": .init(type: "number", description: "0.0 to 1.0", enumValues: nil),
                    "needs_reply": .init(type: "boolean", description: "True if this email is addressed to the user and appears to expect a response.", enumValues: nil),
                    "reasoning": .init(type: "string", description: "One sentence explaining the classification.", enumValues: nil),
                    "proposed_new_category_name": .init(
                        type: "string",
                        description: "Optional. Only set this if category_name is \"Other\" AND the email represents a specific, reusable topic worth its own category going forward (not a one-off). Must not duplicate an existing category name. Leave unset otherwise.",
                        enumValues: nil
                    ),
                    "proposed_new_category_reasoning": .init(type: "string", description: "One sentence explaining why this new category is needed, if proposed.", enumValues: nil),
                    "action_item_summary": .init(
                        type: "string",
                        description: "Optional. Set only if the email explicitly requires the user to take a concrete action (fill out a form, pay something, respond to a request, complete a task) — not just \"reading it\" or a generic reply. A short imperative summary, e.g. \"Sign the consent form\". Leave unset if there's no concrete action.",
                        enumValues: nil
                    ),
                    "action_due_date": .init(
                        type: "string",
                        description: "Optional. Only set alongside action_item_summary, and only if the email states or clearly implies a specific deadline/date (e.g. \"ACTION NEEDED by 8/19/2026\", \"due Friday\"). Format strictly as YYYY-MM-DD. Leave unset if no date is given.",
                        enumValues: nil
                    )
                ],
                required: ["category_name", "confidence", "needs_reply"]
            )
        )

        let system = """
        You triage a personal email inbox. Available categories: \(names.joined(separator: ", ")).
        Pick exactly one category per email — use "\(Category.otherName)" only when nothing else fits.
        Also decide whether the email needs a reply: true only if it's addressed to the user personally \
        and appears to expect a response (not newsletters, receipts, automated notifications, or mass mail).
        If, and only if, category_name is "\(Category.otherName)" and the email represents a specific, \
        recurring topic that would be worth its own category going forward (not a one-off), you may \
        optionally propose one via proposed_new_category_name/proposed_new_category_reasoning. Never \
        propose a name that duplicates an existing category. Leave both unset otherwise.
        Separately, if the email requires the user to take a concrete action — not just read or optionally \
        reply, but do something specific like submit a form, make a payment, or complete a task — set \
        action_item_summary to a short imperative description. If the email states or clearly implies a \
        deadline (e.g. "ACTION NEEDED by 8/19/2026", "please respond by Friday"), also set action_due_date \
        in YYYY-MM-DD format. Leave both unset for ordinary mail with nothing concrete to do.
        """

        let userMessage = """
        From: \(email.fromName ?? email.from) <\(email.from)>
        Subject: \(email.subject)
        Preview: \(email.snippet)
        """

        let input = try await client.callTool(system: system, userMessage: userMessage, tool: tool, apiKey: apiKey)

        guard let categoryName = input["category_name"]?.stringValue else {
            throw ClaudeAPIClient.ClaudeAPIError.noToolUseInResponse
        }
        let confidence = input["confidence"]?.doubleValue ?? 0
        let needsReply = input["needs_reply"]?.boolValue ?? false
        let reasoning = input["reasoning"]?.stringValue
        let proposedNewCategoryName = input["proposed_new_category_name"]?.stringValue
        let proposedNewCategoryReasoning = input["proposed_new_category_reasoning"]?.stringValue
        let actionItemSummary = input["action_item_summary"]?.stringValue
        let actionDueDate = input["action_due_date"]?.stringValue.flatMap(Self.parseActionDueDate)

        return CategorizationResult(
            categoryName: categoryName, confidence: confidence, needsReply: needsReply, reasoning: reasoning,
            proposedNewCategoryName: proposedNewCategoryName, proposedNewCategoryReasoning: proposedNewCategoryReasoning,
            actionItemSummary: actionItemSummary, actionDueDate: actionDueDate
        )
    }

    /// Parses the model's YYYY-MM-DD date string in a fixed UTC POSIX locale
    /// so it doesn't depend on the user's calendar/locale settings. Invalid
    /// or malformed dates (the model doesn't always follow format
    /// instructions perfectly) come back nil rather than throwing — a
    /// missing due date just means the action item shows without one.
    static func parseActionDueDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func suggestDraft(email: EmailMessage, bodyHTML: String, apiKey: String) async throws -> DraftResult {
        let tool = ClaudeTool(
            name: "propose_reply",
            description: "Propose a reply to an email for the user to review before sending.",
            inputSchema: ClaudeJSONSchema(
                properties: [
                    "subject": .init(type: "string", description: "Reply subject line.", enumValues: nil),
                    "body": .init(type: "string", description: "Plain-text reply body, ready for human review.", enumValues: nil),
                    "reasoning": .init(type: "string", description: "One sentence on the intent of the reply.", enumValues: nil)
                ],
                required: ["subject", "body"]
            )
        )

        let system = """
        You draft polite, concise reply suggestions for a personal inbox. Never invent facts, \
        commitments, dates, or numbers that aren't present in the original email or provided context. \
        This is a draft for human review only — it will never be sent without the user explicitly \
        reviewing and sending it themselves.
        """

        let userMessage = """
        From: \(email.fromName ?? email.from) <\(email.from)>
        Subject: \(email.subject)

        \(Self.stripHTML(bodyHTML))
        """

        let input = try await client.callTool(system: system, userMessage: userMessage, tool: tool, maxTokens: 1024, apiKey: apiKey)

        guard let subject = input["subject"]?.stringValue, let body = input["body"]?.stringValue else {
            throw ClaudeAPIClient.ClaudeAPIError.noToolUseInResponse
        }
        return DraftResult(subject: subject, body: body, reasoning: input["reasoning"]?.stringValue)
    }

    /// Rough HTML→text stripping for prompt context only (not for display).
    private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(6000)) // keep prompt/token cost bounded
    }
}
