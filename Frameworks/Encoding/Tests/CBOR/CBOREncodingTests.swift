import Encoding
import Testing

struct CBOREncodingTests {
    @Test(arguments: CBORVectors.canonical)
    func `Items encode with the shortest argument`(expected: [UInt8], item: CBOR) {
        #expect(item.encoded == expected)
    }

    @Test
    func `Map keys follow the bytewise order of their encodings`() {
        let map = CBOR.map([
            .text("aa"): .integer(5),
            .integer(-1): .integer(3),
            .text("z"): .integer(4),
            .integer(100): .integer(2),
            .integer(10): .integer(1),
        ])

        #expect(
            map.encoded == [0xa5, 0x0a, 0x01, 0x18, 0x64, 0x02, 0x20, 0x03, 0x61, 0x7a, 0x04, 0x62, 0x61, 0x61, 0x05]
        )
    }
}
