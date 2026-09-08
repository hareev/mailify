import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            CategoriesSettingsView()
                .tabItem { Label("Categories", systemImage: "tag") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
            SyncSettingsView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct SyncSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncCoordinator: SyncCoordinator

    var body: some View {
        Form {
            Section {
                HStack {
                    Button {
                        Task { await syncCoordinator.syncNow() }
                    } label: {
                        if syncCoordinator.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Sync Now")
                        }
                    }
                    .disabled(syncCoordinator.isSyncing)

                    Spacer()

                    if let lastSynced = appState.gmailAccount?.lastSyncedAt {
                        Text("Last synced \(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let lastError = syncCoordinator.lastError {
                    Text(lastError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Manual Sync")
            } footer: {
                Text("Also available from the toolbar (circular arrow icon) and the menu bar, any time.")
            }

            Section {
                HStack {
                    Button {
                        Task { await syncCoordinator.categorizeExistingMail() }
                    } label: {
                        if syncCoordinator.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Categorize Now")
                        }
                    }
                    .disabled(syncCoordinator.isSyncing)

                    Spacer()

                    Text(uncategorizedCount > 0 ? "\(uncategorizedCount) uncategorized" : "All caught up")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let summary = syncCoordinator.lastCategorizeSummary {
                    Text(summary).font(.caption).foregroundStyle(.green)
                }
            } header: {
                Text("Categorization")
            } footer: {
                Text("Runs AI categorization and draft suggestions on mail that's already been synced — no Gmail fetch. Also available from the toolbar (tag icon). Requires an Anthropic API key in Settings → AI.")
            }

            Section {
                Picker("Automatic sync", selection: periodicSyncBinding) {
                    Text("Off").tag(0)
                    ForEach(SyncSettings.availableSyncIntervalMinutes, id: \.self) { minutes in
                        Text(SyncSettings.label(forIntervalMinutes: minutes)).tag(minutes)
                    }
                }
            } header: {
                Text("Automatic Sync")
            } footer: {
                Text("Runs Sync Now automatically on this schedule, even when the app is in the background. This setting persists across relaunches.")
            }

            Section {
                Picker("Sync window", selection: windowDaysBinding) {
                    ForEach(SyncSettings.availableWindowDays, id: \.self) { days in
                        Text(SyncSettings.label(forWindowDays: days)).tag(days)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("History")
            } footer: {
                Text("\"Since last sync\" (default) pulls only what's arrived since the last successful sync, with no fixed cap — falling back to the last 30 days for a brand-new account's first sync. The fixed options cap every sync, including incremental ones, to that many days back.")
            }

            Section {
                Toggle("Ignore Social", isOn: excludeSocialBinding)
                Toggle("Ignore Promotions", isOn: excludePromotionsBinding)
            } header: {
                Text("Focus")
            } footer: {
                Text("Skips Gmail's Social and Promotions tabs during sync, so only Primary-inbox-style mail is pulled in. Applies to future syncs only — mail already synced isn't removed.")
            }
        }
        .formStyle(.grouped)
    }

    private var uncategorizedCount: Int {
        appState.store.uncategorizedMessageCount
    }

    /// Combines periodicSyncEnabled + periodicSyncIntervalMinutes into a
    /// single Picker selection: 0 means "Off", any other value is the
    /// interval in minutes (and implies enabled).
    private var periodicSyncBinding: Binding<Int> {
        Binding(
            get: { syncCoordinator.periodicSyncEnabled ? syncCoordinator.periodicSyncIntervalMinutes : 0 },
            set: { newValue in
                if newValue == 0 {
                    syncCoordinator.setPeriodicSyncEnabled(false)
                } else {
                    syncCoordinator.setPeriodicSyncIntervalMinutes(newValue)
                    syncCoordinator.setPeriodicSyncEnabled(true)
                }
            }
        )
    }

    private var windowDaysBinding: Binding<Int> {
        Binding(
            get: { appState.store.syncSettings.windowDays },
            set: { newValue in appState.mutateStore { $0.syncSettings.windowDays = newValue } }
        )
    }

    private var excludeSocialBinding: Binding<Bool> {
        Binding(
            get: { appState.store.syncSettings.excludeSocial },
            set: { newValue in appState.mutateStore { $0.syncSettings.excludeSocial = newValue } }
        )
    }

    private var excludePromotionsBinding: Binding<Bool> {
        Binding(
            get: { appState.store.syncSettings.excludePromotions },
            set: { newValue in appState.mutateStore { $0.syncSettings.excludePromotions = newValue } }
        )
    }
}
