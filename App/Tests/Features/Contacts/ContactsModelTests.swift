import Foundation
import RPC
import Testing
@testable import Transactions
@testable import widgets

/// Checks how the contacts list sorts and groups addresses, which addresses rules check against, and how it saves,
/// favorites, and deletes.
@MainActor
struct ContactsModelTests {
    /// The account payments leave from is never offered as a recipient.
    @Test func `The sending account isn't listed`() async {
        #expect(await ContactsFixtures.model().accounts.map(\.address) == [ContactsFixtures.savings])
    }

    /// Contacts sort by name without regard to case.
    @Test func `Contacts sort by name`() async {
        #expect(await ContactsFixtures.model().contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// Favorites list favorite accounts before favorite contacts.
    @Test func `Favorites list accounts before contacts`() async {
        #expect(await ContactsFixtures.model().favorites.map(\.name) == ["Savings", "Alice"])
    }

    /// Recents list only unsaved addresses, since saved ones show under their names.
    @Test func `Recents leave out saved addresses`() async {
        #expect(await ContactsFixtures.model().recents.map(\.address) == [ContactsFixtures.recent])
    }

    /// Payments are kept newest first.
    @Test func `Payments are newest first`() async {
        #expect(await ContactsFixtures.model().payments.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// Rules check a recipient against every address the person used: accounts, contacts, and paid addresses.
    @Test func `The recipient context lists every address the person used`() async {
        let known = Set(await ContactsFixtures.model().recipientContext.knownAddresses)
        #expect(known == [ContactsFixtures.sending, ContactsFixtures.savings, ContactsFixtures.alice,
                          ContactsFixtures.bruno, ContactsFixtures.recent])
    }

    /// The first-payment rule sees only the addresses the person paid.
    @Test func `The recipient context lists the paid addresses`() async {
        #expect(await ContactsFixtures.model().recipientContext.paidAddresses == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// A saved address is paid under its name; an unsaved one has none.
    @Test func `Recipients are named only when saved`() async {
        let contacts = await ContactsFixtures.model()
        #expect(contacts.recipient(for: ContactsFixtures.alice) == PaymentRecipient(address: ContactsFixtures.alice, name: "Alice"))
        #expect(contacts.recipient(for: ContactsFixtures.recent).name == nil)
    }

    /// A saved address is found under its name; an unsaved one isn't.
    @Test func `Saved addresses are found`() async {
        let contacts = await ContactsFixtures.model()
        #expect(contacts.saved(at: ContactsFixtures.alice)?.name == "Alice")
        #expect(contacts.saved(at: ContactsFixtures.savings)?.name == "Savings")
        #expect(contacts.saved(at: ContactsFixtures.recent) == nil)
    }

    /// Accounts, contacts, and unsaved recents have rows; the sending account and unpaid strangers don't.
    @Test func `Only listed addresses have rows`() async {
        let contacts = await ContactsFixtures.model()
        #expect([ContactsFixtures.savings, ContactsFixtures.alice, ContactsFixtures.recent].allSatisfy(contacts.lists))
        #expect(!contacts.lists(ContactsFixtures.sending))
        #expect(!contacts.lists(ContactsFixtures.stranger))
    }

    /// A new contact joins the list in name order.
    @Test func `Saving a new contact keeps the list sorted`() async {
        let contacts = await ContactsFixtures.model()
        contacts.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        #expect(contacts.contacts.map(\.name) == ["Aaron", "Alice", "bruno"])
    }

    /// Saving a contact with an existing identity replaces it instead of adding another.
    @Test func `Saving an edited contact replaces it`() async throws {
        let contacts = await ContactsFixtures.model()
        var bruno = try #require(contacts.saved(at: ContactsFixtures.bruno))
        bruno.name = "Zed"
        contacts.save(bruno)
        #expect(contacts.contacts.map(\.name) == ["Alice", "Zed"])
    }

    /// Deleting a contact who was paid lists their address under Recents again.
    @Test func `Deleting a paid contact returns them to Recents`() async throws {
        let contacts = await ContactsFixtures.model()
        contacts.delete(try #require(contacts.contacts.first { $0.address == ContactsFixtures.alice }))
        #expect(contacts.contacts.map(\.address) == [ContactsFixtures.bruno])
        #expect(contacts.recents.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// Accounts and contacts both join and leave Favorites.
    @Test func `Favorites toggle for accounts and contacts`() async throws {
        let contacts = await ContactsFixtures.model()
        let savings = try #require(contacts.accounts.first { $0.address == ContactsFixtures.savings })
        let bruno = try #require(contacts.contacts.first { $0.address == ContactsFixtures.bruno })
        contacts[isFavorite: savings].toggle()
        contacts[isFavorite: bruno].toggle()
        #expect(!contacts[isFavorite: savings])
        #expect(contacts[isFavorite: bruno])
        #expect(contacts.favorites.map(\.name) == ["Alice", "bruno"])
    }

    /// A wallet with only its sending account and no contacts or payments has no one to list.
    @Test func `A list without anyone else is empty`() async {
        let services = ContactsFixtures.services(addressBook: StoredValue(), recents: StoredValue())
        let contacts = ContactsModel(sendingAccount: ContactsFixtures.sending, wallet: ContactsFixtures.wallet,
                                     network: .mainnet,
                                     accounts: [Contact(name: "Main", address: ContactsFixtures.sending)],
                                     services: services)

        await contacts.load()

        #expect(contacts.isLoaded)
        #expect(contacts.isEmpty)
    }

    /// New, edited, deleted, and favorite contacts and favorite accounts are read back by the next list, as after a
    /// relaunch, and every window hears about each change.
    @Test func `Changes are saved for the next list`() async throws {
        let services = ContactsFixtures.services()
        let contacts = await ContactsFixtures.model(services: services)
        var bruno = try #require(contacts.saved(at: ContactsFixtures.bruno))
        let alice = try #require(contacts.saved(at: ContactsFixtures.alice))
        let savings = try #require(contacts.saved(at: ContactsFixtures.savings))

        contacts.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        bruno.name = "Zed"
        contacts.save(bruno)
        contacts.delete(alice)
        contacts[isFavorite: bruno] = true
        contacts[isFavorite: savings] = false
        await contacts.load()

        let relaunched = await ContactsFixtures.model(services: services)
        #expect(relaunched.contacts.map(\.name) == ["Aaron", "Zed"])
        #expect(relaunched.favorites.map(\.name) == ["Zed"])
        #expect(services.revision.value == 5)
    }

    /// A landed payment is listed first, an address keeps only its latest payment, and each wallet keeps its own
    /// payments on each network.
    @Test func `Recent payments are kept per network`() async throws {
        let services = ContactsFixtures.services()
        let mainnet = await ContactsFixtures.model(services: services)

        mainnet.record(RecentPayment(address: ContactsFixtures.recent, date: Date(timeIntervalSince1970: 3_000)))
        await mainnet.load()

        let relaunched = await ContactsFixtures.model(services: services)
        #expect(relaunched.payments.map(\.address) == [ContactsFixtures.recent, ContactsFixtures.alice])
        #expect(await ContactsFixtures.model(services: services, network: .devnet).payments.isEmpty)
    }

    /// Only the latest payments are kept, so Recents stays short.
    @Test func `Only the latest ten payments are kept`() async throws {
        let services = ContactsFixtures.services(recents: StoredValue())
        let contacts = await ContactsFixtures.model(services: services)
        let addresses = try (1...12).map { try Address(bytes: [UInt8](repeating: UInt8($0), count: 32)) }

        for (index, address) in addresses.enumerated() {
            contacts.record(RecentPayment(address: address, date: Date(timeIntervalSince1970: Double(index))))
        }
        await contacts.load()

        let expected = Array(addresses.reversed().prefix(ContactsModel.recentLimit))
        #expect(contacts.payments.map(\.address) == expected)
        #expect(await ContactsFixtures.model(services: services).payments.map(\.address) == expected)
    }

    /// Storage that can't be read is reported instead of showing an empty list, and nothing replaces it.
    @Test func `Unreadable contacts are reported, not emptied`() async {
        let addressBook = StoredValue(ContactsFixtures.addressBook, unreadable: true)
        let contacts = await ContactsFixtures.model(services: ContactsFixtures.services(addressBook: addressBook))

        #expect(contacts.isUnreadable)
        #expect(!contacts.isLoaded)
        #expect(await addressBook.value == ContactsFixtures.addressBook)
    }

    /// A change that can't be saved shows an error, and the list returns to what's saved.
    @Test func `A change that can't be saved is undone`() async {
        let addressBook = StoredValue(ContactsFixtures.addressBook, failsSaving: true)
        let contacts = await ContactsFixtures.model(services: ContactsFixtures.services(addressBook: addressBook))

        contacts.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        #expect(contacts.contacts.map(\.name) == ["Aaron", "Alice", "bruno"])
        await contacts.load()

        #expect(contacts.error == .unsaved)
        #expect(contacts.contacts.map(\.name) == ["Alice", "bruno"])
    }
}
