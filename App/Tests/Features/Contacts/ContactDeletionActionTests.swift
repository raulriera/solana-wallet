import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Checks that the deletion action deletes a contact and clears a selection that loses its row.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactDeletionActionTests {
    /// Holds the tab's selected address, as the split view's state does.
    @MainActor
    private final class Selection {
        var address: Address?
    }

    /// A deleted contact who was paid stays selected under Recents; one who wasn't leaves nothing selected.
    @Test(arguments: [(ContactsFixtures.alice, ContactsFixtures.alice), (ContactsFixtures.bruno, nil)])
    func `Deleting the selected contact keeps only a paid address selected`(address: Address,
                                                                          selected: Address?) async throws {
        let tab = await ContactsFixtures.tab()
        let contact = try #require(tab.lists.saved(at: address))
        let selection = Selection()
        selection.address = address
        let action = ContactDeletionAction(contacts: tab.model, lists: tab.lists, store: tab.store,
                                           selection: Binding { selection.address } set: { selection.address = $0 })

        action(contact)
        await tab.load()

        #expect(selection.address == selected)
        #expect(tab.lists.saved(at: address) == nil)
    }

    /// Deleting a contact that isn't selected leaves the selection as it was.
    @Test func `Deleting another contact keeps the selection`() async throws {
        let tab = await ContactsFixtures.tab()
        let bruno = try #require(tab.lists.saved(at: ContactsFixtures.bruno))
        let selection = Selection()
        selection.address = ContactsFixtures.recent
        let action = ContactDeletionAction(contacts: tab.model, lists: tab.lists, store: tab.store,
                                           selection: Binding { selection.address } set: { selection.address = $0 })

        action(bruno)

        #expect(selection.address == ContactsFixtures.recent)
    }
}
