import Redaction
import Testing

struct ArrayEraseTests {
    @Test(arguments: [[], [0xff], Array(UInt8.min...UInt8.max)] as [[UInt8]])
    func `Erasing zeroes every byte`(bytes: [UInt8]) {
        var erased = bytes

        erased.erase()

        #expect(erased == [UInt8](repeating: 0, count: bytes.count))
    }
}
