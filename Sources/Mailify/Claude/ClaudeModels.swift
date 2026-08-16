import Foundation

// MARK: - Messages API request

struct ClaudeMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [ClaudeMessage]
    let tools: [ClaudeTool]?
    let toolChoice: ClaudeToolChoice?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case toolChoice = "tool_choice"
    }
}

struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

struct ClaudeTool: Encodable {
    let name: String
    let description: String
    let inputSchema: ClaudeJSONSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct ClaudeToolChoice: Encodable {
    let type = "tool"
    let name: String
}

/// Minimal hand-rolled JSON Schema representation, just enough for the two
/// tool definitions this app needs (flat object of string/number/bool props).
struct ClaudeJSONSchema: Encodable {
    struct Property: Encodable {
        var type: String
        var description: String?
        var enumValues: [String]?

        enum CodingKeys: String, CodingKey {
            case type, description
            case enumValues = "enum"
        }
    }

    let type = "object"
    let properties: [String: Property]
    let required: [String]
}

// MARK: - Messages API response

struct ClaudeMessageResponse: Decodable {
    let content: [ClaudeContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
    let name: String?
    let input: [String: ClaudeJSONValue]?
}

/// Decodes an arbitrary JSON value from a Claude tool_use `input` object
/// without pulling in a third-party dependency.
enum ClaudeJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

struct ClaudeErrorResponse: Decodable {
    struct ErrorBody: Decodable {
        let type: String
        let message: String
    }
    let error: ErrorBody
}
