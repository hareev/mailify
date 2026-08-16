import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncCoordinator: SyncCoordinator
    @Binding var selection: SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            Section("Mail") {
                Label("All Mail", systemImage: "envelope").tag(SidebarSelection.allMail)

                Label {
                    HStack {
                        Text("Suggestions")
                        Spacer()
                        if appState.pendingSuggestionCount > 0 {
                            CountBadge(count: appState.pendingSuggestionCount)
                        }
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
                .tag(SidebarSelection.suggestions)

                Label {
                    HStack {
                        Text("New Categories")
                        Spacer()
                        if appState.pendingCategorySuggestionCount > 0 {
                            CountBadge(count: appState.pendingCategorySuggestionCount)
                        }
                    }
                } icon: {
                    Image(systemName: "folder.badge.plus")
                }
                .tag(SidebarSelection.categorySuggestions)

                Label {
                    HStack {
                        Text("Action Items")
                        Spacer()
                        if appState.pendingActionItemCount > 0 {
                            CountBadge(count: appState.pendingActionItemCount)
                        }
                    }
                } icon: {
                    Image(systemName: "checklist")
                }
                .tag(SidebarSelection.actionItems)
            }

            Section("Categories") {
                ForEach(sortedCategories) { category in
                    Label {
                        HStack {
                            Text(category.name)
                            Spacer()
                            if let count = needsReplyCounts[category.id], count > 0 {
                                CountBadge(count: count)
                            }
                        }
                    } icon: {
                        Circle().fill(Color(hex: category.colorHex)).frame(width: 10, height: 10)
                    }
                    .tag(SidebarSelection.category(category.id))
                }
            }

            Section {
                Label("Settings", systemImage: "gearshape").tag(SidebarSelection.settings)
            }
        }
        .navigationTitle("Mailify")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await syncCoordinator.syncNow() }
                } label: {
                    if syncCoordinator.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(syncCoordinator.isSyncing)
                .help("Sync Now — fetches new mail from Gmail, then categorizes and drafts suggestions")
            }

            ToolbarItem {
                Button {
                    Task { await syncCoordinator.categorizeExistingMail() }
                } label: {
                    Image(systemName: "tag")
                        .overlay(alignment: .topTrailing) {
                            if uncategorizedCount > 0 {
                                ToolbarCountBadge(count: uncategorizedCount)
                            }
                        }
                }
                .disabled(syncCoordinator.isSyncing)
                .help(uncategorizedCount > 0
                    ? "Categorize \(uncategorizedCount) already-synced email\(uncategorizedCount == 1 ? "" : "s") — no Gmail fetch, just AI categorization + draft suggestions"
                    : "Categorize existing mail — nothing uncategorized right now")
            }
        }
    }

    private var uncategorizedCount: Int {
        appState.store.uncategorizedMessageCount
    }

    /// Categories sorted by needs-reply count (importance) descending, with
    /// `sortOrder` ascending as a deterministic tiebreak for equal/zero
    /// counts. Settings → Categories deliberately keeps sorting by
    /// `sortOrder` alone — re-sorting under the user's cursor mid-edit
    /// whenever a background sync changes a count would be a real editing
    /// regression there, not just a style difference.
    private var sortedCategories: [Category] {
        let counts = needsReplyCounts
        return appState.store.categories.sorted { lhs, rhs in
            let l = counts[lhs.id] ?? 0
            let r = counts[rhs.id] ?? 0
            if l != r { return l > r }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var needsReplyCounts: [UUID: Int] {
        appState.store.needsReplyCountByCategory
    }
}

private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.tint, in: Capsule())
            .foregroundStyle(.white)
    }
}

/// Small corner-overlay badge sized for a toolbar icon, where CountBadge's
/// list-row padding would be too large. Caps the label at "99+" so a big
/// backlog doesn't blow out the toolbar icon's bounds.
private struct ToolbarCountBadge: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9)).fontWeight(.bold)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(.red, in: Capsule())
            .foregroundStyle(.white)
            .offset(x: 8, y: -6)
    }
}
