import Testing
import Transactions
@testable import widgets

/// Checks how the recipient sheet rejects pasted text, warns about addresses, and saves what each purpose asks for.
@MainActor
struct RecipientEntryModelTests {
    /// An empty sheet explains nothing and can't be confirmed.
    @Test func `An empty sheet can't be confirmed`() {
        let entry = RecipientEntryModel(contacts: ContactsFixtures.model())
        #expect(entry.rejection == nil)
        #expect(!entry.canConfirm)
    }

    /// Spaces and line breaks around a pasted address are ignored.
    @Test func `Pasted addresses are trimmed`() {
        let entry = RecipientEntryModel(contacts: ContactsFixtures.model())
        entry.paste("  \(ContactsFixtures.stranger.value)\n")
        #expect(entry.address == ContactsFixtures.stranger)
        #expect(entry.canConfirm)
    }

    /// Pasted text that isn't an address is rejected, and each rejected paste signals again.
    @Test func `Text that isn't an address is rejected each time`() {
        let entry = RecipientEntryModel(contacts: ContactsFixtures.model())
        entry.paste("not an address")
        entry.paste("not an address")
        #expect(entry.rejection == .notAddress)
        #expect(entry.rejectionCount == 2)
        #expect(!entry.canConfirm)
    }

    /// The account payments leave from can't be its own recipient.
    @Test func `The sending account is rejected`() {
        let entry = RecipientEntryModel(contacts: ContactsFixtures.model())
        entry.paste(ContactsFixtures.sending.value)
        #expect(entry.rejection == .sendingAccount)
        #expect(!entry.canConfirm)
    }

    /// The sheet warns about a look-alike address, but leaves the first-payment note to the review.
    @Test func `Look-alike addresses are warned about`() {
        let entry = RecipientEntryModel(contacts: ContactsFixtures.model())
        entry.paste(ContactsFixtures.aliceLookAlike.value)
        #expect(entry.warnings == [.lookAlike])
    }

    /// A payment to a new address without a name pays it without saving it.
    @Test func `An unnamed payment saves nothing`() {
        let contacts = ContactsFixtures.model()
        let entry = RecipientEntryModel(contacts: contacts)
        entry.paste(ContactsFixtures.stranger.value)
        entry.confirm()
        #expect(entry.confirmation == .init(purpose: .payment, address: ContactsFixtures.stranger))
        #expect(contacts.saved(at: ContactsFixtures.stranger) == nil)
    }

    /// A payment to a new address with a name also saves it as a contact.
    @Test func `A named payment saves a contact`() {
        let contacts = ContactsFixtures.model()
        let entry = RecipientEntryModel(contacts: contacts)
        entry.paste(ContactsFixtures.stranger.value)
        entry.name = "  Chiara "
        entry.confirm()
        #expect(entry.confirmation == .init(purpose: .payment, address: ContactsFixtures.stranger))
        #expect(contacts.saved(at: ContactsFixtures.stranger)?.name == "Chiara")
    }

    /// A payment to a saved address keeps its saved name and adds no contact.
    @Test func `A payment to a saved address keeps its name`() {
        let contacts = ContactsFixtures.model()
        let entry = RecipientEntryModel(contacts: contacts)
        entry.paste(ContactsFixtures.alice.value)
        entry.name = "Someone Else"
        entry.confirm()
        #expect(entry.saved?.name == "Alice")
        #expect(entry.confirmation?.address == ContactsFixtures.alice)
        #expect(contacts.contacts.count == 2)
    }

    /// Saving a contact needs a name.
    @Test func `A new contact needs a name`() {
        let contacts = ContactsFixtures.model()
        let entry = RecipientEntryModel(savingContactAt: ContactsFixtures.recent, contacts: contacts)
        #expect(!entry.canConfirm)
        entry.name = "Dmitri"
        entry.confirm()
        #expect(contacts.saved(at: ContactsFixtures.recent)?.name == "Dmitri")
    }

    /// An address that's already saved can't be saved again as another contact.
    @Test func `A saved address can't become another contact`() {
        let entry = RecipientEntryModel(savingContactAt: ContactsFixtures.alice, contacts: ContactsFixtures.model())
        entry.name = "Alice Again"
        #expect(entry.rejection == .alreadySaved)
        #expect(!entry.canConfirm)
    }

    /// Editing a contact keeps its identity and favorite, and its own address isn't counted as already saved.
    @Test func `Editing keeps the contact's identity`() throws {
        let contacts = ContactsFixtures.model()
        let alice = try #require(contacts.saved(at: ContactsFixtures.alice))
        let entry = RecipientEntryModel(editing: alice, contacts: contacts)
        #expect(entry.rejection == nil)
        #expect(entry.canConfirm)
        entry.name = "Alicia"
        entry.paste(ContactsFixtures.stranger.value)
        entry.confirm()
        let edited = try #require(contacts.saved(at: ContactsFixtures.stranger))
        #expect(edited.id == alice.id)
        #expect(edited.name == "Alicia")
        #expect(edited.isFavorite)
        #expect(contacts.saved(at: ContactsFixtures.alice) == nil)
        #expect(entry.confirmation == .init(purpose: .edit(alice), address: ContactsFixtures.stranger))
    }

    /// An edit can't move a contact onto an address another contact or account already has.
    @Test func `An edit can't take another saved address`() throws {
        let contacts = ContactsFixtures.model()
        let alice = try #require(contacts.saved(at: ContactsFixtures.alice))
        let entry = RecipientEntryModel(editing: alice, contacts: contacts)
        entry.paste(ContactsFixtures.bruno.value)
        #expect(entry.rejection == .alreadySaved)
        #expect(!entry.canConfirm)
    }
}
