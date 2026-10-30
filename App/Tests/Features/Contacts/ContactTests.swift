import Testing
@testable import widgets

struct ContactTests {
    @Test func `Each new contact has its own identity`() {
        let first = Contact(name: "Alice", address: ContactsFixtures.alice)
        let second = Contact(name: "Alice", address: ContactsFixtures.alice)
        #expect(first.id != second.id)
    }
}
