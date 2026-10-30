import Testing
@testable import RPC

struct RequestBatchingTests {
    @Test
    func `Unique elements keep the order of their first occurrence`() {
        #expect(["b", "a", "b", "c", "a"].uniqued() == ["b", "a", "c"])
    }

    @Test(arguments: [(0, [Int]()), (3, [3]), (4, [3, 1]), (5, [3, 2])])
    func `Batches are full except the last and keep every element in order`(count: Int, sizes: [Int]) {
        let elements = Array(0..<count)

        let batches = elements.batches(of: 3)

        #expect(batches.map(\.count) == sizes)
        #expect(batches.flatMap(\.self) == elements)
    }
}
