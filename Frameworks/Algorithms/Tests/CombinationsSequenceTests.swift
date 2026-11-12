import Algorithms
import Testing

struct CombinationsSequenceTests {
    @Test
    func `Combinations follow the elements' positions`() {
        #expect(Array([1, 2, 3].combinations(ofCount: 2)) == [[1, 2], [1, 3], [2, 3]])
    }

    @Test
    func `Single combinations are the elements`() {
        #expect(Array([3, 1].combinations(ofCount: 1)) == [[3], [1]])
    }

    @Test
    func `A count of zero has one empty combination`() {
        #expect(Array([1, 2].combinations(ofCount: 0)) == [[]])
    }

    @Test(arguments: [([Int](), 1), ([1, 2], 3)])
    func `Counts above the collection's have no combinations`(elements: [Int], count: Int) {
        #expect(Array(elements.combinations(ofCount: count)).isEmpty)
    }

    @Test
    func `A range of counts lists smaller combinations first`() {
        #expect(Array([1, 2, 3].combinations(ofCount: 1...2)) == [[1], [2], [3], [1, 2], [1, 3], [2, 3]])
    }
}
