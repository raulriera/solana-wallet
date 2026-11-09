import Testing
@testable import Privacy

struct CollectionCombinationsTests {
    @Test
    func `Combinations follow the elements' positions`() {
        #expect([1, 2, 3].combinations(ofCount: 2) == [[1, 2], [1, 3], [2, 3]])
    }

    @Test
    func `Single combinations are the elements`() {
        #expect([3, 1].combinations(ofCount: 1) == [[3], [1]])
    }

    @Test
    func `A count of zero has one empty combination`() {
        #expect([1, 2].combinations(ofCount: 0) == [[]])
    }

    @Test(arguments: [([Int](), 1), ([1, 2], 3)])
    func `Counts above the collection's have no combinations`(elements: [Int], count: Int) {
        #expect(elements.combinations(ofCount: count).isEmpty)
    }
}
