import Testing
@testable import Privacy

struct SequenceOverflowTests {
    @Test(arguments: [
        ([UInt64](), UInt64(0), false),
        ([4, 6], 10, false),
        ([.max, 0], .max, false),
        ([.max, 1], 0, true),
        ([.max, 1, 5], 5, true),
    ])
    func `Sums report overflow with the truncated sum`(amounts: [UInt64], sum: UInt64, overflow: Bool) {
        let result = amounts.sumReportingOverflow()

        #expect(result.partialValue == sum)
        #expect(result.overflow == overflow)
    }
}
