import Testing
import Transactions
@testable import widgets

/// Checks how the recipient sheet rejects pasted text, warns about addresses, and confirms the contact each purpose
/// saves.
@MainActor
struct RecipientEntryModelTests {
    /// An empty sheet explains nothing and can't be confirmed.
    @Test func `An empty sheet can't be confirmed`() {
        let entry = RecipientEntryModel()
        #expect(entry.rejection == nil)
        #expect(!entry.canConfirm)
    }

    /// Spaces and line breaks around a pasted address are ignored.
    @Test func `Pasted addresses are trimmed`() {
        let entry = RecipientEntryModel()
        entry.paste("  \(ContactsFixtures.stranger.value)\n", in: ContactsFixtures.lists)
        #expect(entry.address == ContactsFixtures.stranger)
        #expect(entry.canConfirm)
    }

    /// Pasted text that isn't an address is rejected, and each rejected paste signals again.
    @Test func `Text that isn't an address is rejected each time`() {
        let entry = RecipientEntryModel()
        entry.paste("not an address", in: ContactsFixtures.lists)
        entry.paste("not an address", in: ContactsFixtures.lists)
        #expect(entry.rejection == .notAddress)
        #expect(entry.rejectionCount == 2)
        #expect(!entry.canConfirm)
    }

    /// The account payments leave from can't be its own recipient.
    @Test func `The sending account is rejected`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.sending.value, in: ContactsFixtures.lists)
        #expect(entry.rejection == .sendingAccount)
        #expect(!entry.canConfirm)
    }

    /// The sheet warns about a look-alike address, but leaves the first-payment note to the review.
    @Test func `Look-alike addresses are warned about`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.aliceLookAlike.value, in: ContactsFixtures.lists)
        #expect(entry.warnings == [.lookAlike])
    }

    /// A payment to a new address without a name pays it without saving it.
    @Test func `An unnamed payment saves nothing`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.stranger.value, in: ContactsFixtures.lists)
        entry.confirm()
        #expect(entry.confirmation == .init(purpose: .payment, address: ContactsFixtures.stranger))
    }

    /// A payment to a new address with a name also saves it as a contact.
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

    /// A payment to a saved address keeps its saved name and adds no contact.
    @Test func `A payment to a saved address keeps its name`() {
        let entry = RecipientEntryModel()
        entry.paste(ContactsFixtures.alice.value, in: ContactsFixtures.lists)
        entry.name = "Someone Else"
        entry.confirm()
        #expect(entry.saved?.name == "Alice")
        #expect(entry.confirmation == .init(purpose: .payment, address: ContactsFixtures.alice))
    }

    /// Saving a contact needs a name.
    @Test func `A new contact needs a name`() {
        let entry = RecipientEntryModel(savingContactAt: ContactsFixtures.recent, in: ContactsFixtures.lists)
        #expect(!entry.canConfirm)
        entry.name = "Dmitri"
        entry.confirm()
        #expect(entry.confirmation?.purpose == .addContact)
        #expect(entry.confirmation?.contact?.name == "Dmitri")
        #expect(entry.confirmation?.contact?.address == ContactsFixtures.recent)
    }

    /// An address that's already saved can't be saved again as another contact.
    @Test func `A saved address can't become another contact`() {
        let entry = RecipientEntryModel(savingContactAt: ContactsFixtures.alice, in: ContactsFixtures.lists)
        entry.name = "Alice Again"
        #expect(entry.rejection == .alreadySaved)
        #expect(!entry.canConfirm)
    }

    /// Editing a contact keeps its identity and favorite, and its own address isn't counted as already saved.
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

    /// An edit can't move a contact onto an address another contact or account already has.
    @Test(arguments: [ContactsFixtures.bruno, ContactsFixtures.savings])
    func `An edit can't take another saved address`(address: Address) throws {
        let alice = try #require(ContactsFixtures.lists.saved(at: ContactsFixtures.alice))
        let entry = RecipientEntryModel(editing: alice, in: ContactsFixtures.lists)
        entry.paste(address.value, in: ContactsFixtures.lists)
        #expect(entry.rejection == .alreadySaved)
        #expect(!entry.canConfirm)
    }
}
