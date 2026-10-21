import Testing
@testable import widgets

/// Checks that contacts keep their own identity.
struct ContactTests {
    /// Two contacts with the same name and address are still different contacts.
    @Test func `Each new contact has its own identity`() {
        let first = Contact(name: "Alice", address: ContactsFixtures.alice)
        let second = Contact(name: "Alice", address: ContactsFixtures.alice)
        #expect(first.id != second.id)
    }
}
