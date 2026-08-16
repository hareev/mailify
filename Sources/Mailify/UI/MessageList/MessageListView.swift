import SwiftUI

enum SidebarSelection: Hashable {
    case allMail
    case category(UUID)
    case suggestions
    case categorySuggestions
    case actionItems
    case settings
}

struct MessageListView: View {
    @EnvironmentObject var appState: AppState
    let selection: SidebarSelection
    @Binding var selectedMessageID: String?

    private var messages: [EmailMessage] {
        let active = appState.store.messages.filter { !$0.isArchivedOrDeleted }
        let filtered: [EmailMessage]
        switch selection {
        case .allMail:
            filtered = active
        case .category(let categoryID):
            filtered = active.filter { $0.categoryID == categoryID }
        case .suggestions, .categorySuggestions, .actionItems, .settings:
            filtered = []
        }
        return filtered.sorted { $0.receivedAt > $1.receivedAt }
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                ContentUnavailableView("No messages", systemImage: "envelope", description: Text("Sync to fetch mail, or pick a different category."))
            } else {
                List(messages, selection: $selectedMessageID) { message in
                    MessageRow(message: message, category: appState.store.categories.first { $0.id == message.categoryID })
                        .tag(message.id)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch selection {
        case .allMail: return "All Mail"
        case .category(let id): return appState.store.categories.first { $0.id == id }?.name ?? "Category"
        case .suggestions: return "Suggestions"
        case .categorySuggestions: return "New Categories"
        case .actionItems: return "Action Items"
        case .settings: return "Settings"
        }
    }
}

private struct MessageRow: View {
    let message: EmailMessage
    let category: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.fromName ?? message.from)
                    .fontWeight(message.isRead ? .regular : .semibold)
                    .lineLimit(1)
                Spacer()
                Text(message.receivedAt.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                .fontWeight(message.isRead ? .regular : .semibold)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let category {
                    CategoryBadge(category: category)
                }
                if message.needsReply {
                    Label("Needs reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            Text(message.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
