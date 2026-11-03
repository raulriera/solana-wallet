import Encoding
import Testing
@testable import Attestation

struct NitroAttestationDocumentTests {
    private static let pcr = CBOR.bytes([UInt8](repeating: 0x0f, count: 48))

    private static let measured: [CBOR.Key: CBOR] = [.integer(0): pcr, .integer(1): pcr, .integer(2): pcr]

    @Test
    func `The recorded document decodes with the devnet prover's values`() throws {
        let recorded = try RecordedNitroAttestation.load(named: "RecordedDevnetNitroAttestation")
        let (message, certificate, bundle) = try recorded.decoded()
        let pins = try #require(NitroPolicyFixture.deployment(named: "DevnetNitroPolicy").measurements.first)

        let document = try NitroAttestationDocument(decoding: message.payload)

        #expect(document.measurement.pcr0 == (try fixtureBytes(pins.pcr0)))
        #expect(document.measurement.pcr1 == (try fixtureBytes(pins.pcr1)))
        #expect(document.measurement.pcr2 == (try fixtureBytes(pins.pcr2)))
        #expect(document.certificate == certificate)
        #expect(document.bundle == bundle)
        #expect(document.publicKey == (try fixtureBytes(recorded.attestation.hpkePublicKey)))
        #expect(document.nonce == (try fixtureBytes(recorded.nonce)))
        #expect(document.userData?.count == 64)
    }

    @Test(arguments: ["module_id", "timestamp", "digest", "pcrs", "certificate", "cabundle"])
    func `A document without a required field is rejected`(field: String) throws {
        var fields = try NitroCBORCases.load().documentFields()
        fields[.text(field)] = nil

        #expect(throws: NitroPolicy.ValidationError.malformed) { try Self.document(fields) }
    }

    @Test(arguments: [
        ("module_id", .bytes(Array("i-0123-enc0123".utf8))),
        ("module_id", .text("")),
        ("timestamp", .integer(-1)),
        ("timestamp", .text("1800000000000")),
        ("digest", .bytes(Array("SHA384".utf8))),
        ("pcrs", .array([pcr, pcr, pcr])),
        ("pcrs", .map(measured.merging([.text("3"): pcr]) { $1 })),
        ("pcrs", .map(measured.merging([.integer(-1): pcr]) { $1 })),
        ("pcrs", .map(measured.merging([.integer(32): pcr]) { $1 })),
        ("pcrs", .map(measured.merging([.integer(3): .text("0f")]) { $1 })),
        ("pcrs", .map(measured.merging([.integer(2): .bytes([UInt8](repeating: 0x0f, count: 32))]) { $1 })),
        ("pcrs", .map(measured.filter { $0.key != .integer(2) })),
        ("certificate", .text("30")),
        ("cabundle", .bytes([0x30])),
        ("cabundle", .array([.text("30")])),
        ("cabundle", .array(Array(repeating: .bytes([0x30]), count: 9))),
        ("public_key", .text("22")),
        ("user_data", .array(Array(repeating: .integer(0), count: 64))),
        ("nonce", .integer(1)),
    ] as [(String, CBOR)])
    func `A field of another type or out of range is rejected`(field: String, value: CBOR) throws {
        var fields = try NitroCBORCases.load().documentFields()
        fields[.text(field)] = value

        #expect(throws: NitroPolicy.ValidationError.malformed) { try Self.document(fields) }
    }

    @Test(arguments: [("SHA256", 32), ("SHA512", 64), ("sha384", 48)])
    func `PCRs of a digest other than SHA384 are rejected`(digest: String, byteCount: Int) throws {
        var fields = try NitroCBORCases.load().documentFields()
        let pcr = CBOR.bytes([UInt8](repeating: 0x0f, count: byteCount))
        fields[.text("digest")] = .text(digest)
        fields[.text("pcrs")] = .map([.integer(0): pcr, .integer(1): pcr, .integer(2): pcr])

        #expect(throws: NitroPolicy.ValidationError.unsupportedDigest) { try Self.document(fields) }
    }

    @Test
    func `A zero PCR0 is rejected as a debug enclave`() throws {
        var fields = try NitroCBORCases.load().documentFields()
        let zero = CBOR.bytes([UInt8](repeating: 0, count: 48))
        fields[.text("pcrs")] = .map(Self.measured.merging([.integer(0): zero]) { $1 })

        #expect(throws: NitroPolicy.ValidationError.debugEnclave) { try Self.document(fields) }
    }

    @Test
    func `A document may have up to 16 fields`() throws {
        var fields = try NitroCBORCases.load().documentFields()
        while fields.count < 16 {
            fields[.integer(Int64(fields.count))] = .null
        }

        #expect(throws: Never.self) { try Self.document(fields) }
        fields[.text("extra")] = .null
        #expect(throws: NitroPolicy.ValidationError.malformed) { try Self.document(fields) }
    }

    @Test
    func `Every PCR index below 32 and a bundle of 8 certificates decode`() throws {
        var fields = try NitroCBORCases.load().documentFields()
        let pcrs = (0..<32).map { (CBOR.Key.integer($0), Self.pcr) }
        fields[.text("pcrs")] = .map(Dictionary(uniqueKeysWithValues: pcrs))
        fields[.text("cabundle")] = .array(Array(repeating: .bytes([0x30]), count: 8))

        let document = try Self.document(fields)

        #expect(document.measurement.pcr2 == [UInt8](repeating: 0x0f, count: 48))
        #expect(document.bundle.count == 8)
    }

    @Test(arguments: [nil, .null] as [CBOR?])
    func `Absent or null optional fields decode as nil`(value: CBOR?) throws {
        var fields = try NitroCBORCases.load().documentFields()
        for field in ["public_key", "user_data", "nonce"] {
            fields[.text(field)] = value
        }

        let document = try Self.document(fields)

        #expect(document.publicKey == nil)
        #expect(document.userData == nil)
        #expect(document.nonce == nil)
    }

    private static func document(_ fields: [CBOR.Key: CBOR]) throws -> NitroAttestationDocument {
        try NitroAttestationDocument(decoding: CBOR.map(fields).encoded)
    }
}
