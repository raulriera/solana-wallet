import Encoding
import Testing

struct CBORTests {
    @Test(arguments: CBORVectors.canonical + [
        (
            [0x9f, 0x01, 0x82, 0x02, 0x03, 0x9f, 0x04, 0x05, 0xff, 0xff],
            .array([.integer(1), .array([.integer(2), .integer(3)]), .array([.integer(4), .integer(5)])])
        ),
        (
            [0xbf, 0x63, 0x46, 0x75, 0x6e, 0xf5, 0x63, 0x41, 0x6d, 0x74, 0x21, 0xff],
            .map([.text("Fun"): .boolean(true), .text("Amt"): .integer(-2)])
        ),
    ] as [([UInt8], CBOR)])
    func `Items in the subset decode`(bytes: [UInt8], expected: CBOR) throws {
        #expect(try CBOR(decoding: bytes) == expected)
    }

    @Test(arguments: [
        ([0x1b, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], .integerOutOfRange),
        ([0x3b, 0x00, 0x1f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], .integerOutOfRange),
        ([0xf9, 0x00, 0x00], .float),
        ([0xfa, 0x47, 0xc3, 0x50, 0x00], .float),
        ([0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a], .float),
        ([0xf7], .unsupportedSimpleValue),
        ([0xe0], .unsupportedSimpleValue),
        ([0xf8, 0x14], .unsupportedSimpleValue),
        ([0x5f, 0x42, 0x01, 0x02, 0xff], .indefiniteString),
        ([0x7f, 0x61, 0x61, 0xff], .indefiniteString),
        ([0x61, 0xff], .invalidText),
        ([0x62, 0xc0, 0x80], .invalidText),
        ([0xa2, 0x01, 0x02, 0x01, 0x03], .duplicateKey),
        ([0xa1, 0x40, 0x01], .invalidKey),
        ([0x00, 0x00], .trailingBytes),
        ([0x18], .malformed),
        ([0x42, 0x01], .malformed),
        ([0x1c], .malformed),
        ([0x1f], .malformed),
        ([0xff], .malformed),
        ([0x82, 0x01], .malformed),
        ([0x9f, 0x01], .malformed),
        ([0xbf, 0x01, 0xff], .malformed),
    ] as [([UInt8], CBOR.ValidationError)])
    func `Items outside the subset are rejected`(bytes: [UInt8], error: CBOR.ValidationError) {
        #expect(throws: error) { try CBOR(decoding: bytes) }
    }

    @Test
    func `Containers nest at most 16 deep, not counting definite empty ones`() {
        let sixteenArrays = [UInt8](repeating: 0x81, count: 16) + [0x80]
        let seventeenArrays = [UInt8](repeating: 0x81, count: 17) + [0x00]
        let indefiniteEmptyArray = [UInt8](repeating: 0x81, count: 16) + [0x9f, 0xff]
        let sixteenMaps = Array([[UInt8]](repeating: [0xa1, 0x00], count: 16).joined()) + [0xa0]
        let seventeenMaps = Array([[UInt8]](repeating: [0xa1, 0x00], count: 17).joined()) + [0x00]

        #expect(throws: Never.self) { try CBOR(decoding: sixteenArrays) }
        #expect(throws: Never.self) { try CBOR(decoding: sixteenMaps) }
        #expect(throws: CBOR.ValidationError.nestedTooDeep) { try CBOR(decoding: seventeenArrays) }
        #expect(throws: CBOR.ValidationError.nestedTooDeep) { try CBOR(decoding: indefiniteEmptyArray) }
        #expect(throws: CBOR.ValidationError.nestedTooDeep) { try CBOR(decoding: seventeenMaps) }
    }

    @Test(arguments: [[0xd2, 0x80], [0x80]] as [[UInt8]])
    func `The allowed tag may precede the item`(bytes: [UInt8]) throws {
        #expect(try CBOR(decoding: bytes, allowingLeadingTag: 18) == .array([]))
    }

    @Test(arguments: [
        ([0xd2, 0x80], nil),
        ([0xd3, 0x80], 18),
        ([0xd2, 0xd2, 0x80], 18),
        ([0x81, 0xd2, 0x80], 18),
    ] as [([UInt8], UInt64?)])
    func `Other, repeated, and nested tags are rejected`(bytes: [UInt8], tag: UInt64?) {
        #expect(throws: CBOR.ValidationError.unsupportedTag) { try CBOR(decoding: bytes, allowingLeadingTag: tag) }
    }
}
