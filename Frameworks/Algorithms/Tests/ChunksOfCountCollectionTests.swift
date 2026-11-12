import Algorithms
import Testing

struct ChunksOfCountCollectionTests {
    @Test(arguments: [
        (0, [[Int]]()),
        (3, [[0, 1, 2]]),
        (4, [[0, 1, 2], [3]]),
        (5, [[0, 1, 2], [3, 4]]),
        (6, [[0, 1, 2], [3, 4, 5]]),
    ])
    func `Chunks are full except the last and keep every element in order`(count: Int, chunks: [[Int]]) {
        let elementChunks = Array(0..<count).chunks(ofCount: 3)

        #expect(elementChunks.map(Array.init) == chunks)
        #expect(elementChunks.count == chunks.count)
    }

    @Test
    func `A chunk count larger than the collection makes one chunk`() {
        #expect([1, 2, 3].chunks(ofCount: .max).map(Array.init) == [[1, 2, 3]])
    }

    @Test
    func `Chunks of a slice keep the slice's indices`() {
        let words = ["a", "b", "c", "d", "e"][1...]

        #expect(words.chunks(ofCount: 2).map(\.startIndex) == [1, 3])
    }
}
