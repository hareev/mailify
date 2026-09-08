// Mailify eval suite — ordered checks, one section per feature, run with:
//   ./run-eval.sh
//
// This is a plain script (must be named main.swift — Swift only allows
// top-level executable code in a file with that exact name when compiling
// multiple files together), compiled directly against Sources/Mailify/*.swift
// by run-eval.sh (not a SwiftPM target), by necessity: on a Command-Line-
// Tools-only machine (no full Xcode.app), XCTest.framework doesn't exist at
// all; swift-testing's framework, while present under CLT, needed two extra
// linker rpaths to even dlopen, and even then silently discovered and ran
// zero tests while still exiting 0 (false "pass"); and a *second* SwiftPM
// executable target depending on Mailify fails to link at all, because
// SwiftPM only lets `@testable import` resolve against an executable
// target's object files inside its own special testTarget machinery — a
// plain target dependency doesn't get that treatment. Compiling this file
// straight alongside Mailify's sources sidesteps all three problems at once:
// if this compiles and runs, every check in it ran, full stop.
//
// Sections, in order:
//   1. Persistence       — does the store load/save correctly, incl. old files
//   2. Sync query        — does a sync request the right mail from Gmail
//   3. OAuth authorize    — is the redirect Google will actually accept
//   4. OAuth loopback     — is the redirect response parsed correctly
//   5. Category suggestions — AI-proposed category decision logic
//   6. Action items       — due-date parsing, persistence, pending count
// Exits 0 if every check passed, 1 otherwise — safe to wire into a pre-push
// hook or CI later without needing a real Xcode install.
//
// Note: everything here is internal (not `@testable`) since this compiles
// as part of the same module as Sources/Mailify/*.swift, not as an importer
// of it.

import Foundation
import CryptoKit

var totalCount = 0
var failureCount = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    totalCount += 1
    if condition() {
        print("PASS  \(name)")
    } else {
        failureCount += 1
        print("FAIL  \(name)")
    }
}

func section(_ title: String) {
    print("\n== \(title) ==")
}

// MARK: - 1. Persistence — AppStore Codable + backward compatibility

section("1. Persistence — AppStore Codable + backward compatibility")

do {
    let store = AppStore()
    check("fresh AppStore() has version 1", store.version == 1)
    check("fresh AppStore() has no accounts", store.accounts.isEmpty)
    check("fresh AppStore() has default syncSettings", store.syncSettings == SyncSettings())
}

do {
    var store = AppStore()
    store.syncSettings = SyncSettings(windowDays: 7, excludeSocial: true, excludePromotions: false)
    store.categories = [Category(name: "Test", colorHex: "#ABCDEF", sortOrder: 0)]

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(store) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AppStore.self, from: data) {
            check("round-trip preserves syncSettings", decoded.syncSettings == store.syncSettings)
            check("round-trip preserves categories", decoded.categories == store.categories)
        } else {
            check("round-trip decode succeeds", false)
        }
    } else {
        check("round-trip encode succeeds", false)
    }
}

do {
    let accountID = UUID()
    let categoryID = UUID()
    func msg(id: String, categoryID: UUID?, archived: Bool) -> EmailMessage {
        EmailMessage(id: id, accountID: accountID, threadID: "t-\(id)", from: "a@b.com", subject: "s", snippet: "", receivedAt: Date(), categoryID: categoryID, isArchivedOrDeleted: archived)
    }
    var store = AppStore()
    store.messages = [
        msg(id: "1", categoryID: categoryID, archived: false),  // categorized — excluded
        msg(id: "2", categoryID: nil, archived: false),          // uncategorized, active — counted
        msg(id: "3", categoryID: nil, archived: false),          // uncategorized, active — counted
        msg(id: "4", categoryID: nil, archived: true)             // uncategorized but archived — excluded
    ]
    check("uncategorizedMessageCount counts only active, uncategorized mail", store.uncategorizedMessageCount == 2)
}

do {
    // Regression guard: disconnecting Gmail used to delete its account row
    // entirely, so reconnecting (even to the same mailbox) created a fresh
    // Account.id, orphaning every previously-synced message's accountID and
    // silently excluding them from every account-scoped filter forever —
    // this happened for real (twice) to a live user's 153-message backlog.
    let staleAccountID1 = UUID()
    let staleAccountID2 = UUID()
    let currentAccountID = UUID()
    var store = AppStore()
    store.accounts = [Account(id: currentAccountID, provider: "gmail", emailAddress: "user@example.com")]
    store.messages = [
        EmailMessage(id: "1", accountID: staleAccountID1, threadID: "t1", from: "a@b.com", subject: "s1", snippet: "", receivedAt: Date()),
        EmailMessage(id: "2", accountID: staleAccountID2, threadID: "t2", from: "a@b.com", subject: "s2", snippet: "", receivedAt: Date()),
        EmailMessage(id: "3", accountID: currentAccountID, threadID: "t3", from: "a@b.com", subject: "s3", snippet: "", receivedAt: Date())
    ]
    store.reassignOrphanedMessages(toAccountMatchingProvider: "gmail")
    check("reassignOrphanedMessages heals messages pointing at stale account ids", store.messages.allSatisfy { $0.accountID == currentAccountID })
}

do {
    // No Gmail account connected at all — nothing to reassign to, and this
    // must not crash or otherwise touch the messages.
    var store = AppStore()
    let someAccountID = UUID()
    store.messages = [EmailMessage(id: "1", accountID: someAccountID, threadID: "t1", from: "a@b.com", subject: "s1", snippet: "", receivedAt: Date())]
    store.reassignOrphanedMessages(toAccountMatchingProvider: "gmail")
    check("reassignOrphanedMessages is a no-op when no matching account exists", store.messages.first?.accountID == someAccountID)
}

do {
    // Regression guard: a store.json written before `syncSettings` existed
    // must still load, with the field defaulted, instead of being treated
    // as corrupt and silently backed up/discarded by AppStorePersistence.
    let legacyJSON = Data("""
    {"version": 1, "accounts": [], "categories": [], "messages": [], "suggestions": []}
    """.utf8)
    if let decoded = try? JSONDecoder().decode(AppStore.self, from: legacyJSON) {
        check("decodes a store.json missing the syncSettings key", decoded.syncSettings == SyncSettings())
    } else {
        check("decodes a store.json missing the syncSettings key", false)
    }
}

do {
    // Regression guard: a syncSettings object written before periodicSync*
    // existed (i.e. from the previous SyncSettings shape) must still decode,
    // with those two fields defaulted, instead of failing this nested decode
    // and taking down the whole AppStore load with it.
    let legacySyncSettingsJSON = Data("""
    {"windowDays": 7, "excludeSocial": true, "excludePromotions": false}
    """.utf8)
    if let decoded = try? JSONDecoder().decode(SyncSettings.self, from: legacySyncSettingsJSON) {
        check("decodes a SyncSettings missing periodicSync* keys", decoded.periodicSyncEnabled == false && decoded.periodicSyncIntervalMinutes == 60)
        check("decodes a SyncSettings missing periodicSync* keys, preserves existing fields", decoded.windowDays == 7 && decoded.excludeSocial == true)
    } else {
        check("decodes a SyncSettings missing periodicSync* keys", false)
    }
}

do {
    if let decoded = try? JSONDecoder().decode(AppStore.self, from: Data("{}".utf8)) {
        check("decodes an empty JSON object without throwing", decoded.version == 1 && decoded.syncSettings == SyncSettings())
    } else {
        check("decodes an empty JSON object without throwing", false)
    }
}

// MARK: - 2. Sync query building — GmailProvider.buildQuery

section("2. Sync query building — GmailProvider.buildQuery")

check(
    "first sync (since == nil) uses the configured window as-is",
    GmailProvider.buildQuery(since: nil, filter: SyncSettings(windowDays: 7, excludeSocial: false, excludePromotions: false)) == "newer_than:7d"
)

check(
    "incremental sync narrower than the window uses elapsed time",
    // elapsed = 2 days, +1 rounding = 3d, well under the 30d window
    GmailProvider.buildQuery(since: Date().addingTimeInterval(-2 * 86400), filter: SyncSettings(windowDays: 30, excludeSocial: false, excludePromotions: false)) == "newer_than:3d"
)

check(
    "incremental sync wider than the window is clamped to the window (regression guard)",
    // Before this fix, windowDays only applied to the very first sync. Once
    // account.lastSyncedAt was set (after any sync at all), changing the
    // History picker in Settings → Sync had no effect on future syncs.
    GmailProvider.buildQuery(since: Date().addingTimeInterval(-90 * 86400), filter: SyncSettings(windowDays: 7, excludeSocial: false, excludePromotions: false)) == "newer_than:7d"
)

check(
    "excluding Social adds -category:social",
    GmailProvider.buildQuery(since: nil, filter: SyncSettings(windowDays: 30, excludeSocial: true, excludePromotions: false)) == "newer_than:30d -category:social"
)

check(
    "excluding Promotions adds -category:promotions",
    GmailProvider.buildQuery(since: nil, filter: SyncSettings(windowDays: 30, excludeSocial: false, excludePromotions: true)) == "newer_than:30d -category:promotions"
)

check(
    "excluding both combines both clauses",
    GmailProvider.buildQuery(since: nil, filter: SyncSettings(windowDays: 60, excludeSocial: true, excludePromotions: true)) == "newer_than:60d -category:social -category:promotions"
)

check(
    "default SyncSettings (sinceLastSync) with no previous sync falls back to the 30-day initial backfill",
    GmailProvider.buildQuery(since: nil, filter: SyncSettings()) == "newer_than:30d"
)

check(
    "sinceLastSync uses the full elapsed time uncapped, unlike a fixed window",
    // elapsed = 90 days, +1 rounding = 91d — a fixed window would clamp this,
    // sinceLastSync (windowDays == 0) must not.
    GmailProvider.buildQuery(since: Date().addingTimeInterval(-90 * 86400), filter: SyncSettings(windowDays: SyncSettings.sinceLastSync)) == "newer_than:91d"
)

check(
    "sinceLastSync still narrows down for a recent incremental sync",
    // elapsed = 2 days, +1 rounding = 3d
    GmailProvider.buildQuery(since: Date().addingTimeInterval(-2 * 86400), filter: SyncSettings(windowDays: SyncSettings.sinceLastSync)) == "newer_than:3d"
)

check("periodic sync interval label: 15 -> 'Every 15 minutes'", SyncSettings.label(forIntervalMinutes: 15) == "Every 15 minutes")
check("periodic sync interval label: 60 -> 'Every hour'", SyncSettings.label(forIntervalMinutes: 60) == "Every hour")
check("periodic sync interval label: 480 -> 'Every 8 hours'", SyncSettings.label(forIntervalMinutes: 480) == "Every 8 hours")
check("periodic sync interval label: 1440 -> 'Every 24 hours'", SyncSettings.label(forIntervalMinutes: 1440) == "Every 24 hours")

check("sync window label: sinceLastSync -> 'Since last sync'", SyncSettings.label(forWindowDays: SyncSettings.sinceLastSync) == "Since last sync")
check("sync window label: 7 -> 'Last 7 days'", SyncSettings.label(forWindowDays: 7) == "Last 7 days")

// MARK: - 3. OAuth authorize URL + PKCE — GmailOAuthManager

section("3. OAuth authorize URL + PKCE — GmailOAuthManager")

do {
    // Regression guard: Google rejects custom URI scheme redirects for
    // Desktop-app OAuth clients with "Error 400: redirect_uri_mismatch" (see
    // GmailOAuthManager's doc comment). If redirect_uri here ever stops
    // starting with "http://127.0.0.1", sign-in is broken again.
    let url = GmailOAuthManager.makeAuthorizeURL(
        clientID: "test-client-id",
        redirectURI: "http://127.0.0.1:54321/oauth2redirect",
        scopes: "scope-a scope-b",
        challenge: "test-challenge"
    )
    let redirectURI = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "redirect_uri" })?.value
    check("authorize URL redirect_uri matches what was passed in", redirectURI == "http://127.0.0.1:54321/oauth2redirect")
    check("authorize URL redirect_uri is a loopback address, not a custom scheme", redirectURI?.hasPrefix("http://127.0.0.1") == true)
}

do {
    let url = GmailOAuthManager.makeAuthorizeURL(
        clientID: "test-client-id",
        redirectURI: "http://127.0.0.1:1/oauth2redirect",
        scopes: "scope-a",
        challenge: "test-challenge"
    )
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let names = Set(items.map(\.name))
    check("authorize URL has every required PKCE param", names.isSuperset(of: [
        "client_id", "redirect_uri", "response_type", "scope",
        "code_challenge", "code_challenge_method", "access_type", "prompt"
    ]))
    check("response_type is code", items.first(where: { $0.name == "response_type" })?.value == "code")
    check("code_challenge_method is S256", items.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
}

do {
    let verifier = GmailOAuthManager.randomCodeVerifier()
    check("code verifier is >= 43 chars (RFC 7636 minimum)", verifier.count >= 43)
    check("code verifier has no '+' character", !verifier.contains("+"))
    check("code verifier has no '/' character", !verifier.contains("/"))
    check("code verifier has no '=' character", !verifier.contains("="))
}

do {
    let verifier = "test-verifier-value"
    let expectedHash = SHA256.hash(data: Data(verifier.utf8))
    let expectedChallenge = Data(expectedHash).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    check("code challenge is base64url(SHA256(verifier)), per RFC 7636", GmailOAuthManager.codeChallenge(for: verifier) == expectedChallenge)
}

// MARK: - 4. OAuth loopback redirect parsing — OAuthLoopbackServer

section("4. OAuth loopback redirect parsing — OAuthLoopbackServer")

do {
    let request = "GET /oauth2redirect?code=4/0AY0e-g7abc123&scope=email HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n"
    if case .success(let code) = OAuthLoopbackServer.parseAuthorizationResult(fromRequestText: request) {
        check("extracts the authorization code from a successful redirect", code == "4/0AY0e-g7abc123")
    } else {
        check("extracts the authorization code from a successful redirect", false)
    }
}

do {
    let request = "GET /oauth2redirect?error=access_denied HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n"
    if case .failure(.authorizationFailed(let reason)) = OAuthLoopbackServer.parseAuthorizationResult(fromRequestText: request) {
        check("surfaces Google's error= param when consent is denied", reason == "access_denied")
    } else {
        check("surfaces Google's error= param when consent is denied", false)
    }
}

do {
    let request = "GET /oauth2redirect HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n"
    if case .failure(.authorizationFailed(let reason)) = OAuthLoopbackServer.parseAuthorizationResult(fromRequestText: request) {
        check("falls back to unknown_error when neither code nor error is present", reason == "unknown_error")
    } else {
        check("falls back to unknown_error when neither code nor error is present", false)
    }
}

do {
    let request = "GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n"
    if case .failure(.authorizationFailed(let reason)) = OAuthLoopbackServer.parseAuthorizationResult(fromRequestText: request) {
        check("an unrelated request doesn't crash the parser", reason == "unknown_error")
    } else {
        check("an unrelated request doesn't crash the parser", false)
    }
}

// MARK: - 5. Category suggestions — decision logic + palette + persistence

section("5. Category suggestions — decision logic + palette + persistence")

do {
    let legacyJSON = Data("""
    {"version": 1, "accounts": [], "categories": [], "messages": [], "suggestions": []}
    """.utf8)
    if let decoded = try? JSONDecoder().decode(AppStore.self, from: legacyJSON) {
        check("decodes a store.json missing the categorySuggestions key", decoded.categorySuggestions.isEmpty)
    } else {
        check("decodes a store.json missing the categorySuggestions key", false)
    }
}

check("nextSuggestionColor with nothing avoided returns the palette's first color", Category.nextSuggestionColor(avoiding: []) == Category.suggestionPalette[0])
check("nextSuggestionColor skips a hex already in use (case-insensitive)", Category.nextSuggestionColor(avoiding: [Category.suggestionPalette[0].lowercased()]) == Category.suggestionPalette[1])
check("nextSuggestionColor cycles once the whole palette is exhausted", Category.nextSuggestionColor(avoiding: Category.suggestionPalette) == Category.suggestionPalette[Category.suggestionPalette.count % Category.suggestionPalette.count])

do {
    let decision = CategorySuggestion.decide(
        classifiedCategoryName: "Job",
        proposedRawName: "Freelance Clients",
        existingCategories: Category.seedDefaults(),
        existingSuggestions: []
    )
    check("decide() ignores a proposal when not classified as Other (defensive guard)", decision == .ignore)
}

do {
    let decision = CategorySuggestion.decide(
        classifiedCategoryName: Category.otherName,
        proposedRawName: "   ",
        existingCategories: Category.seedDefaults(),
        existingSuggestions: []
    )
    check("decide() ignores an empty/whitespace-only proposed name", decision == .ignore)
}

do {
    let decision = CategorySuggestion.decide(
        classifiedCategoryName: Category.otherName,
        proposedRawName: "school",
        existingCategories: Category.seedDefaults(),
        existingSuggestions: []
    )
    check("decide() ignores a name colliding with an existing category (case-insensitive)", decision == .ignore)
}

do {
    let existingSuggestion = CategorySuggestion(proposedName: "Travel", proposedColorHex: "#F87171", sourceMessageIDs: ["msg-1"])
    let decision = CategorySuggestion.decide(
        classifiedCategoryName: Category.otherName,
        proposedRawName: "travel",
        existingCategories: Category.seedDefaults(),
        existingSuggestions: [existingSuggestion]
    )
    check("decide() merges into a matching pending suggestion (case-insensitive)", decision == .mergeInto(existingSuggestion.id))
}

do {
    let decision = CategorySuggestion.decide(
        classifiedCategoryName: Category.otherName,
        proposedRawName: "Travel",
        existingCategories: Category.seedDefaults(),
        existingSuggestions: []
    )
    if case .create(let name, let colorHex) = decision {
        check("decide() proposes creation with the trimmed name", name == "Travel")
        check("decide() proposes creation with a color not already used by an existing category", !Category.seedDefaults().map(\.colorHex).contains(colorHex))
    } else {
        check("decide() returns .create when nothing else applies", false)
    }
}

// MARK: - 6. Action items — due-date parsing + persistence + pending count

section("6. Action items — due-date parsing + persistence + pending count")

do {
    let legacyJSON = Data("""
    {"version": 1, "accounts": [], "categories": [], "messages": [], "suggestions": []}
    """.utf8)
    if let decoded = try? JSONDecoder().decode(AppStore.self, from: legacyJSON) {
        check("decodes a store.json missing the actionItems key", decoded.actionItems.isEmpty)
    } else {
        check("decodes a store.json missing the actionItems key", false)
    }
}

do {
    var store = AppStore()
    store.actionItems = [
        ActionItem(emailMessageID: "m1", summary: "Sign consent form", status: .pending),
        ActionItem(emailMessageID: "m2", summary: "Pay invoice", status: .done),
        ActionItem(emailMessageID: "m3", summary: "RSVP", status: .dismissed)
    ]
    check("pendingActionItemCount counts only .pending items", store.pendingActionItemCount == 1)
}

check("parseActionDueDate parses a well-formed YYYY-MM-DD date", ClaudeAgentService.parseActionDueDate("2026-08-19") != nil)
check("parseActionDueDate returns nil for a malformed date string", ClaudeAgentService.parseActionDueDate("August 19th") == nil)
check("parseActionDueDate returns nil for an empty string", ClaudeAgentService.parseActionDueDate("") == nil)

if let parsed = ClaudeAgentService.parseActionDueDate("2026-08-19") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let components = calendar.dateComponents([.year, .month, .day], from: parsed)
    check("parseActionDueDate parses year/month/day correctly", components.year == 2026 && components.month == 8 && components.day == 19)
}

// MARK: - Summary

print("\n\(totalCount - failureCount)/\(totalCount) passed")
if failureCount > 0 {
    print("\(failureCount) FAILED")
    exit(1)
} else {
    print("All checks passed.")
    exit(0)
}
