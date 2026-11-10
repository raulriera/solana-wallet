import Testing
@testable import widgets

struct OptionalPresentationTests {
    @Test
    func `A value is presented only while it is present`() {
        let present: Int? = 1
        let absent: Int? = nil
        let presentations = (present.isPresented, absent.isPresented)

        #expect(presentations == (true, false))
    }

    @Test
    func `Dismissing clears the value`() {
        var value: Int? = 1

        value.isPresented = false

        #expect(value == nil)
    }

    @Test
    func `Presenting keeps the value`() {
        var value: Int? = 1

        value.isPresented = true

        #expect(value == 1)
    }
}
