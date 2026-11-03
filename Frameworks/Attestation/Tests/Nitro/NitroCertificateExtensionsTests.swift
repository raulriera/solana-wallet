import Encoding
import Testing
@testable import Attestation

struct NitroCertificateExtensionsTests {
    @Test(arguments: [
        (
            [0x30, 0x0e, 0x06, 0x03, 0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x01, 0x86],
            NitroCertificate.Extension(
                oid: [0x55, 0x1d, 0x0f],
                isCritical: true,
                value: [0x03, 0x02, 0x01, 0x86]
            )
        ),
        (
            [0x30, 0x0b, 0x06, 0x03, 0x55, 0x1d, 0x0f, 0x04, 0x04, 0x03, 0x02, 0x06, 0xc0],
            NitroCertificate.Extension(
                oid: [0x55, 0x1d, 0x0f],
                isCritical: false,
                value: [0x03, 0x02, 0x06, 0xc0]
            )
        ),
    ] as [([UInt8], NitroCertificate.Extension)])
    func `Extensions read their OID, critical flag, and value`(
        bytes: [UInt8],
        expected: NitroCertificate.Extension
    ) throws {
        #expect(try NitroCertificate.Extension(decoding: DER(decoding: bytes)) == expected)
    }

    @Test(arguments: [
        ([0x30, 0x00], .notCertificateAuthority),
        ([0x30, 0x03, 0x01, 0x01, 0xff], .isCertificateAuthority(maxPathLength: nil)),
        ([0x30, 0x06, 0x01, 0x01, 0xff, 0x02, 0x01, 0x02], .isCertificateAuthority(maxPathLength: 2)),
    ] as [([UInt8], NitroCertificate.BasicConstraints)])
    func `Basic constraints read their certificate authority flag and path length`(
        bytes: [UInt8],
        expected: NitroCertificate.BasicConstraints
    ) throws {
        #expect(try NitroCertificate.BasicConstraints(decoding: bytes) == expected)
    }

    @Test(arguments: [
        ([0x30, 0x03, 0x02, 0x01, 0x00], .malformed),
        ([0x30, 0x06, 0x02, 0x01, 0x00, 0x01, 0x01, 0xff], .malformed),
        ([0x01, 0x01, 0xff], .malformed),
        ([0x30, 0x03, 0x01, 0x01, 0x00], .invalidBoolean),
        ([0x30, 0x06, 0x01, 0x01, 0xff, 0x02, 0x01, 0xff], .invalidInteger),
    ] as [([UInt8], NitroCertificate.ValidationError)])
    func `Basic constraints outside RFC 5280's form are rejected`(
        bytes: [UInt8],
        error: NitroCertificate.ValidationError
    ) {
        #expect(throws: error) { try NitroCertificate.BasicConstraints(decoding: bytes) }
    }

    @Test(arguments: [
        ([0x03, 0x02, 0x07, 0x80], NitroCertificate.KeyUsage(digitalSignature: true, keyCertSign: false)),
        ([0x03, 0x02, 0x06, 0xc0], NitroCertificate.KeyUsage(digitalSignature: true, keyCertSign: false)),
        ([0x03, 0x02, 0x02, 0x04], NitroCertificate.KeyUsage(digitalSignature: false, keyCertSign: true)),
        ([0x03, 0x02, 0x01, 0x86], NitroCertificate.KeyUsage(digitalSignature: true, keyCertSign: true)),
        ([0x03, 0x03, 0x07, 0x00, 0x80], NitroCertificate.KeyUsage(digitalSignature: false, keyCertSign: false)),
    ] as [([UInt8], NitroCertificate.KeyUsage)])
    func `Key usage reads digital signature from bit 0 and certificate signing from bit 5`(
        bytes: [UInt8],
        expected: NitroCertificate.KeyUsage
    ) throws {
        #expect(try NitroCertificate.KeyUsage(decoding: bytes) == expected)
    }

    @Test(arguments: [
        ([0x03, 0x01, 0x00], .invalidBitString),
        ([0x03, 0x02, 0x00, 0x00], .invalidBitString),
        ([0x03, 0x02, 0x01, 0x04], .invalidBitString),
        ([0x03, 0x02, 0x01, 0x87], .invalidBitString),
        ([0x04, 0x01, 0x00], .malformed),
    ] as [([UInt8], NitroCertificate.ValidationError)])
    func `Key usage with no bits, trailing zero bits, or another type is rejected`(
        bytes: [UInt8],
        error: NitroCertificate.ValidationError
    ) {
        #expect(throws: error) { try NitroCertificate.KeyUsage(decoding: bytes) }
    }
}
