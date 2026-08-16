import SwiftUI

struct ActionItemQueueView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncCoordinator: SyncCoordinator

    /// Soonest due date first; items with no stated date sort last (they're
    /// still worth doing, just not time-boxed) — same "surface what needs
    /// action, up front" intent as CLAUDE.md's Goal section, applied to the
    /// one signal (a deadline) that makes urgency legible at a glance.
    private var pending: [ActionItem] {
        appState.store.actionItems
            .filter { $0.status == .pending }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l < r
                case (nil, nil): return lhs.createdAt > rhs.createdAt
                case (nil, _): return false
                case (_, nil): return true
                }
            }
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "No action items",
                    systemImage: "checklist",
                    description: Text("Emails that need a concrete action from you — especially ones with a deadline — show up here.")
                )
            } else {
                List(pending) { item in
                    ActionItemRow(
                        item: item,
                        message: appState.store.messages.first { $0.id == item.emailMessageID },
                        onDone: { syncCoordinator.markActionItemDone(item) },
                        onDismiss: { syncCoordinator.dismissActionItem(item) }
                    )
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Action Items")
    }
}

private struct ActionItemRow: View {
    let item: ActionItem
    let message: EmailMessage?
    let onDone: () -> Void
    let onDismiss: () -> Void

    private var isOverdue: Bool {
        guard let dueDate = item.dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.summary).font(.headline)
                Spacer()
                if let dueDate = item.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(isOverdue ? .red : .orange)
                }
            }
            if let message {
                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Spacer()
                Button("Dismiss", role: .cancel) { onDismiss() }
                Button("Mark Done") { onDone() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}
