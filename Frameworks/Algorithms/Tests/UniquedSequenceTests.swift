import Algorithms
import Testing

struct UniquedSequenceTests {
    @Test
    func `Unique elements keep the order of their first occurrence`() {
        #expect(Array(["b", "a", "b", "c", "a"].uniqued()) == ["b", "a", "c"])
    }

    @Test
    func `Elements whose projection repeats an earlier one are left out`() {
        #expect(["dog", "pig", "cat", "ox", "cow", "owl"].uniqued(on: \.first) == ["dog", "pig", "cat", "ox"])
    }
}
