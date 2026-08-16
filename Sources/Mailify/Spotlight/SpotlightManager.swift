import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes emails so they show up in system-wide Spotlight search. Tapping a
/// result hands control back to the app via NSUserActivity (wired up in
/// MailifyApp.swift's onContinueUserActivity).
final class SpotlightManager {
    static let shared = SpotlightManager()

    private let domainIdentifier = "com.hari.mailify.email"

    func index(messages: [EmailMessage], categories: [Category]) {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })

        let items: [CSSearchableItem] = messages.map { message in
            let attrs = CSSearchableItemAttributeSet(contentType: UTType.emailMessage)
            attrs.title = message.subject.isEmpty ? "(no subject)" : message.subject
            attrs.contentDescription = message.snippet
            attrs.emailAddresses = [message.from]
            if let name = message.fromName { attrs.authorNames = [name] }
            attrs.contentCreationDate = message.receivedAt
            if let categoryID = message.categoryID, let name = categoryByID[categoryID] {
                attrs.keywords = [name]
            }

            return CSSearchableItem(uniqueIdentifier: message.id,
                                     domainIdentifier: domainIdentifier,
                                     attributeSet: attrs)
        }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error = error {
                print("Spotlight indexing error: \(error)")
            }
        }
    }

    /// Removes items for messages that are no longer active (archived/deleted
    /// upstream). The old scenario-based version of this manager never did this —
    /// stale items just accumulated forever.
    func deleteStaleItems(messageIDs: [String]) {
        guard !messageIDs.isEmpty else { return }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: messageIDs) { error in
            if let error = error {
                print("Spotlight stale-item removal error: \(error)")
            }
        }
    }
}
