import Testing
@testable import widgets

struct OptionalPresentationTests {
    @Test
    func `A value is presented while present, kept while presenting, and cleared on dismissal`() {
        var value: Int? = 1
        let absent: Int? = nil

        #expect(value.isPresented)
        #expect(!absent.isPresented)
        value.isPresented = true
        #expect(value == 1)
        value.isPresented = false
        #expect(value == nil)
    }
}
