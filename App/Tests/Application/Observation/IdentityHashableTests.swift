import Testing
@testable import widgets

struct IdentityHashableTests {
    private final class Box: IdentityHashable {}

    @Test func `An instance equals only itself`() {
        let box = Box()
        let other = Box()

        #expect(box == box)
        #expect(box != other)
        #expect(Set([box, box, other]).count == 2)
    }
}
