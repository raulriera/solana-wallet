import Encoding
import Testing
@testable import Attestation

struct DERValuesTests {
    @Test(arguments: [
        ([0x02, 0x01, 0x00], []),
        ([0x02, 0x01, 0x7f], [0x7f]),
        ([0x02, 0x02, 0x00, 0x80], [0x80]),
        ([0x02, 0x02, 0x01, 0x00], [0x01, 0x00]),
    ] as [([UInt8], [UInt8])])
    func `Non-negative integers read as their magnitude`(bytes: [UInt8], magnitude: [UInt8]) throws {
        #expect(Array(try DER(decoding: bytes).nonNegativeInteger()) == magnitude)
    }

    @Test(arguments: [
        [0x02, 0x00],
        [0x02, 0x01, 0x80],
        [0x02, 0x01, 0xff],
        [0x02, 0x02, 0x00, 0x7f],
        [0x02, 0x02, 0xff, 0x80],
    ] as [[UInt8]])
    func `Integers that are empty, negative, or not in their shortest form are rejected`(bytes: [UInt8]) throws {
        let value = try DER(decoding: bytes)

        #expect(throws: NitroCertificate.ValidationError.invalidInteger) { try value.nonNegativeInteger() }
    }

    @Test(arguments: [
        ([0x02, 0x01, 0x05], 5),
        ([0x02, 0x08, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], Int.max),
    ] as [([UInt8], Int)])
    func `Integers that Int can represent read as Int`(bytes: [UInt8], value: Int) throws {
        #expect(try DER(decoding: bytes).intValue() == value)
    }

    @Test(arguments: [
        [0x02, 0x09, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        [0x02, 0x09, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    ] as [[UInt8]])
    func `Integers beyond Int are rejected`(bytes: [UInt8]) throws {
        let value = try DER(decoding: bytes)

        #expect(throws: NitroCertificate.ValidationError.invalidInteger) { try value.intValue() }
    }

    @Test(arguments: [
        ([0x03, 0x01, 0x00], [], 0),
        ([0x03, 0x02, 0x07, 0x80], [0x80], 7),
        ([0x03, 0x03, 0x00, 0xab, 0xcd], [0xab, 0xcd], 0),
    ] as [([UInt8], [UInt8], Int)])
    func `Bit strings read as their octets and unused bit count`(
        bytes: [UInt8],
        octets: [UInt8],
        unusedBitCount: Int
    ) throws {
        let bitString = try DER(decoding: bytes).bitString()

        #expect(Array(bitString.octets) == octets)
        #expect(bitString.unusedBitCount == unusedBitCount)
    }

    @Test(arguments: [
        [0x03, 0x00],
        [0x03, 0x01, 0x01],
        [0x03, 0x02, 0x08, 0x00],
        [0x03, 0x02, 0x01, 0x01],
    ] as [[UInt8]])
    func `Bit strings with a missing, out-of-range, or set unused bit are rejected`(bytes: [UInt8]) throws {
        let value = try DER(decoding: bytes)

        #expect(throws: NitroCertificate.ValidationError.invalidBitString) { try value.bitString() }
    }

    @Test
    func `Only bit strings of whole octets read as octets`() throws {
        let whole = try DER(decoding: [0x03, 0x03, 0x00, 0x01, 0x02])
        let partial = try DER(decoding: [0x03, 0x02, 0x01, 0x02])

        #expect(try whole.octetAlignedBitString() == [0x01, 0x02])
        #expect(throws: NitroCertificate.ValidationError.invalidBitString) { try partial.octetAlignedBitString() }
    }

    @Test(arguments: [
        [0x06, 0x03, 0x55, 0x1d, 0x13],
        [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01],
    ] as [[UInt8]])
    func `Object identifiers read as their contents`(bytes: [UInt8]) throws {
        #expect(try DER(decoding: bytes).objectIdentifier() == Array(bytes.dropFirst(2)))
    }

    @Test(arguments: [
        [0x06, 0x00],
        [0x06, 0x02, 0x55, 0x9d],
        [0x06, 0x03, 0x55, 0x80, 0x01],
        [0x06, 0x02, 0x80, 0x01],
    ] as [[UInt8]])
    func `Object identifiers that are empty, padded, or unfinished are rejected`(bytes: [UInt8]) throws {
        let value = try DER(decoding: bytes)

        #expect(throws: NitroCertificate.ValidationError.invalidObjectIdentifier) { try value.objectIdentifier() }
    }

    @Test
    func `Values of another type are malformed`() throws {
        let octetString = try DER(decoding: [0x04, 0x01, 0x00])
        let null = try DER(decoding: [0x05, 0x00])

        #expect(throws: NitroCertificate.ValidationError.malformed) { try octetString.nonNegativeInteger() }
        #expect(throws: NitroCertificate.ValidationError.malformed) { try octetString.bitString() }
        #expect(throws: NitroCertificate.ValidationError.malformed) { try null.objectIdentifier() }
        #expect(throws: NitroCertificate.ValidationError.malformed) { try null.primitive(.octetString) }
        #expect(throws: NitroCertificate.ValidationError.malformed) { try octetString.values() }
        #expect(throws: NitroCertificate.ValidationError.malformed) {
            try DER(decoding: [0x31, 0x00]).fields()
        }
    }

    @Test(arguments: [
        ([0x30, 0x00], false),
        ([0x30, 0x03, 0x01, 0x01, 0xff], true),
    ] as [([UInt8], Bool)])
    func `A default-false boolean reads as false when absent and true when present`(
        bytes: [UInt8],
        value: Bool
    ) throws {
        var fields = try DER(decoding: bytes).fields()

        #expect(try fields.booleanDefaultingToFalse() == value)
        #expect(throws: Never.self) { try fields.finish() }
    }

    @Test(arguments: [
        [0x30, 0x03, 0x01, 0x01, 0x00],
        [0x30, 0x03, 0x01, 0x01, 0x01],
        [0x30, 0x04, 0x01, 0x02, 0xff, 0xff],
    ] as [[UInt8]])
    func `A default-false boolean other than TRUE is rejected`(bytes: [UInt8]) throws {
        var fields = try DER(decoding: bytes).fields()

        #expect(throws: NitroCertificate.ValidationError.invalidBoolean) { try fields.booleanDefaultingToFalse() }
    }

    @Test
    func `An explicit tag reads as the one value inside it`() throws {
        let tag = DER.Identifier(tagWithNumber: 0, tagClass: .contextSpecific)
        var present = try DER(decoding: [0x30, 0x05, 0xa0, 0x03, 0x02, 0x01, 0x02]).fields()
        var absent = try DER(decoding: [0x30, 0x03, 0x02, 0x01, 0x02]).fields()

        #expect(try present.next(explicitlyTagged: tag) == DER(decoding: [0x02, 0x01, 0x02]))
        #expect(try absent.next(explicitlyTagged: tag) == nil)
        #expect(try absent.next() == DER(decoding: [0x02, 0x01, 0x02]))
    }

    @Test(arguments: [
        [0x30, 0x03, 0x80, 0x01, 0x02],
        [0x30, 0x02, 0xa0, 0x00],
        [0x30, 0x08, 0xa0, 0x06, 0x02, 0x01, 0x02, 0x02, 0x01, 0x02],
    ] as [[UInt8]])
    func `An explicit tag that is primitive or doesn't hold one value is malformed`(bytes: [UInt8]) throws {
        let tag = DER.Identifier(tagWithNumber: 0, tagClass: .contextSpecific)
        var fields = try DER(decoding: bytes).fields()

        #expect(throws: NitroCertificate.ValidationError.malformed) { try fields.next(explicitlyTagged: tag) }
    }

    @Test
    func `A reader rejects a missing field and a field left unread`() throws {
        var empty = try DER(decoding: [0x30, 0x00]).fields()
        let unread = try DER(decoding: [0x30, 0x02, 0x05, 0x00]).fields()

        #expect(throws: NitroCertificate.ValidationError.malformed) { try empty.next() }
        #expect(throws: NitroCertificate.ValidationError.malformed) { try unread.finish() }
    }
}
