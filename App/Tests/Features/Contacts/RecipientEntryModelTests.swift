import Testing
import Transactions
@testable import widgets

@MainActor
struct RecipientEntryModelTests {
    @Test func `An empty sheet can't be confirmed`() {
        let entry = RecipientEntryModel()
        #expect(entry.rejection == nil)
        #expect(!entry.canConfirm)
    }

    @Test func `Pasted addresses are trimmed`() {
        let entry = RecipientEntryModel()
        entry.paste("  \(ContactsFixtures.stranger.value)\n", in: ContactsFixtures.lists)
        #expect(entry.address == ContactsFixtures.stranger)
        #expect(entry.canConfirm)
    }

    @Test func `Text that isn't an address is rejected each time`() {
        let entry = RecipientEntryModel()
        entry.paste("not an address", in: ContactsFixtures.lists)
        entry.paste("not an address", in: ContactsFixtures.lists)
        #expect(entry.rejection == .notAddress)
        #expect(entry.rejectionCount == 2)
        #expect(!entry.canConfirm)
    }

    @Test func `The sending account is rejected`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.sending.value, in: ContactsFixtures.lists)
        #expect(entry.rejection == .sendingAccount)
        #expect(!entry.canConfirm)
    }

    @Test func `Look-alike addresses are warned about`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.aliceLookAlike.value, in: ContactsFixtures.lists)
        #expect(entry.warnings == [.lookAlike])
    }

    @Test func `An unnamed payment saves nothing`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.stranger.value, in: ContactsFixtures.lists)
        entry.confirm()
        #expect(entry.confirmation == .init(purpose: .payment, address: ContactsFixtures.stranger))
    }

    @Test func `A named payment saves a contact`() throws {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.stranger.value, in: ContactsFixtures.lists)
        entry.name = "  Chiara "
        entry.confirm()
        let confirmation = try #require(entry.confirmation)
        #expect(confirmation.address == ContactsFixtures.stranger)
        #expect(confirmation.contact?.name == "Chiara")
        #expect(confirmation.contact?.address == ContactsFixtures.stranger)
    }

    @Test func `A payment to a saved address keeps its name`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.alice.value, in: ContactsFixtures.lists)
        entry.name = "Someone Else"
        entry.confirm()
        #expect(entry.saved?.name == "Alice")
        #expect(entry.confirmation == .init(purpose: .payment, address: ContactsFixtures.alice))
    }

    @Test func `A new contact needs a name`() {
        let entry = RecipientEntryModel(savingContactAt: ContactsFixtures.recent, in: ContactsFixtures.lists)
        #expect(!entry.canConfirm)
        entry.name = "Dmitri"
        entry.confirm()
        #expect(entry.confirmation?.purpose == .addContact)
        #expect(entry.confirmation?.contact?.name == "Dmitri")
        #expect(entry.confirmation?.contact?.address == ContactsFixtures.recent)
    }

    @Test func `A saved address can't become another contact`() {
        let entry = RecipientEntryModel(savingContactAt: ContactsFixtures.alice, in: ContactsFixtures.lists)
        entry.name = "Alice Again"
        #expect(entry.rejection == .alreadySaved)
        #expect(!entry.canConfirm)
    }

    @Test func `Editing keeps the contact's identity`() throws {
        let alice = try #require(ContactsFixtures.lists.saved(at: ContactsFixtures.alice))
        let entry = RecipientEntryModel(editing: alice, in: ContactsFixtures.lists)
        #expect(entry.rejection == nil)
        #expect(entry.canConfirm)
        entry.name = "Alicia"
        entry.paste(ContactsFixtures.stranger.value, in: ContactsFixtures.lists)
        entry.confirm()
        let confirmation = try #require(entry.confirmation)
        let edited = try #require(confirmation.contact)
        #expect(edited.id == alice.id)
        #expect(edited.name == "Alicia")
        #expect(edited.address == ContactsFixtures.stranger)
        #expect(edited.isFavorite)
        #expect(confirmation.purpose == .edit(alice))
        #expect(confirmation.address == ContactsFixtures.stranger)
    }

    @Test(arguments: [ContactsFixtures.bruno, ContactsFixtures.savings])
    func `An edit can't take another saved address`(address: Address) throws {
        let alice = try #require(ContactsFixtures.lists.saved(at: ContactsFixtures.alice))
        let entry = RecipientEntryModel(editing: alice, in: ContactsFixtures.lists)
        entry.paste(address.value, in: ContactsFixtures.lists)
        #expect(entry.rejection == .alreadySaved)
        #expect(!entry.canConfirm)
    }
}
