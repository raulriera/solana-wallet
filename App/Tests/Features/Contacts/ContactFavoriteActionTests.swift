import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactFavoriteActionTests {
    @Test func `A contact joins Favorites`() async throws {
        let tab = await ContactsFixtures.tab()
        let bruno = try #require(tab.lists.saved(at: ContactsFixtures.bruno))

        ContactFavoriteAction(contacts: tab.model, lists: tab.lists, store: tab.store)(true, for: bruno)
        await tab.load()

        #expect(tab.store.addressBook.contacts.first { $0.id == bruno.id }?.isFavorite == true)
    }
}
