import SwiftUI
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactDeletionActionTests {
    @MainActor
    private final class Selection {
        var address: Address?
    }

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
