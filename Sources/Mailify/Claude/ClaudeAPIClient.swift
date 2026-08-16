import Foundation

/// Thin URLSession wrapper around the Anthropic Messages API. No SDK — Swift has
/// no official Anthropic SDK, so this follows the documented raw-HTTP shape.
final class ClaudeAPIClient {
    static let model = "claude-opus-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    enum ClaudeAPIError: LocalizedError {
        case missingAPIKey
        case invalidAPIKey
        case http(Int, String)
        case noToolUseInResponse
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "No Anthropic API key set. Add one in Settings → AI."
            case .invalidAPIKey: return "Anthropic API key was rejected. Check it in Settings → AI."
            case .http(let code, let body): return "Claude API error \(code): \(body)"
            case .noToolUseInResponse: return "Claude didn't return the expected structured response."
            case .decoding(let err): return "Failed to decode Claude response: \(err)"
            }
        }
    }

    /// Sends a single-turn message with a forced tool call and returns the
    /// tool's `input` payload. Used for both categorization and draft-suggestion,
    /// since both need reliable structured (not free-text) output.
    ///
    /// Takes `apiKey` as a parameter rather than reading Keychain internally
    /// on every call: a sync can call this once per uncategorized message
    /// (dozens on a first sync), and repeated rapid Keychain reads for the
    /// same item from this app's ad-hoc-signed binary were observed to
    /// intermittently fail/require re-confirmation — reading the key once
    /// per sync (see SyncCoordinator) instead of once per message avoids
    /// hitting that on every single email.
    func callTool(system: String, userMessage: String, tool: ClaudeTool, maxTokens: Int = 512, apiKey: String) async throws -> [String: ClaudeJSONValue] {
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        let requestBody = ClaudeMessageRequest(
            model: Self.model,
            maxTokens: maxTokens,
            system: system,
            messages: [ClaudeMessage(role: "user", content: userMessage)],
            tools: [tool],
            toolChoice: ClaudeToolChoice(name: tool.name)
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.http(0, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ClaudeAPIError.invalidAPIKey }
            let message = (try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8) ?? ""
            throw ClaudeAPIError.http(http.statusCode, message)
        }

        let decoded: ClaudeMessageResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        } catch {
            throw ClaudeAPIError.decoding(error)
        }

        guard let toolUse = decoded.content.first(where: { $0.type == "tool_use" }), let input = toolUse.input else {
            throw ClaudeAPIError.noToolUseInResponse
        }
        return input
    }

    /// Minimal request used by Settings → AI → "Test Key" to validate a key.
    func validateKey(_ apiKey: String) async throws {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ClaudeMessageRequest(
            model: Self.model,
            maxTokens: 8,
            system: nil,
            messages: [ClaudeMessage(role: "user", content: "Reply with OK.")],
            tools: nil,
            toolChoice: nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw ClaudeAPIError.invalidAPIKey }
            let message = (try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data))?.error.message ?? "validation failed"
            throw ClaudeAPIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, message)
        }
    }
}
