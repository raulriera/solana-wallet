import Encoding
import Testing
@testable import Attestation

struct NitroCertificateExtensionsTests {
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
}
