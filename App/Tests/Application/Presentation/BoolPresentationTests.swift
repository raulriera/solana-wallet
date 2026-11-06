import Testing
@testable import widgets

struct BoolPresentationTests {
    @Test
    func `A value is present only while the flag is true`() {
        #expect(true.presented != nil)
        #expect(false.presented == nil)
    }

    @Test
    func `Clearing the value turns the flag off`() {
        var isPresented = true

        isPresented.presented = nil

        #expect(!isPresented)
    }

    @Test
    func `Setting a value turns the flag on`() {
        var isPresented = false

        isPresented.presented = ()

        #expect(isPresented)
    }
}
