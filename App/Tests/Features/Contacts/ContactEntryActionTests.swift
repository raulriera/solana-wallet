import SwiftUI
import Testing
@testable import widgets

@MainActor
struct ContactEntryActionTests {
    @MainActor
    private final class Sheet {
        var entry: RecipientEntryModel?
    }

    @Test func `Saving an address opens the add contact sheet`() throws {
        let sheet = Sheet()
        let action = ContactEntryAction(lists: ContactsFixtures.lists,
                                        entry: Binding { sheet.entry } set: { sheet.entry = $0 })
        action(savingContactAt: ContactsFixtures.stranger)
        let entry = try #require(sheet.entry)
        #expect(entry.purpose == .addContact)
        #expect(entry.address == ContactsFixtures.stranger)
    }

    @Test func `Editing a contact opens the edit sheet with its name`() throws {
        let sheet = Sheet()
        let bruno = try #require(ContactsFixtures.lists.saved(at: ContactsFixtures.bruno))
        let action = ContactEntryAction(lists: ContactsFixtures.lists,
                                        entry: Binding { sheet.entry } set: { sheet.entry = $0 })
        action(editing: bruno)
        let entry = try #require(sheet.entry)
        #expect(entry.purpose == .edit(bruno))
        #expect(entry.name == "bruno")
    }
}
