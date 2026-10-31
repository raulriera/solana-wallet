import CryptoKit
import Encoding
import Foundation
import SwiftASN1
import Testing
import X509
@testable import Attestation

struct NitroCertificateChainTests {
    private struct Chain {
        var certificate: [UInt8]
        var bundle: [[UInt8]]
        var root: [UInt8]
        var date: Date

        func validated() throws -> NitroCertificateChain {
            try NitroCertificateChain(certificate: certificate, bundle: bundle, root: root, at: date)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `The recorded chain yields the key that signs the document`() throws {
        let (message, chain) = try Self.recorded()

        #expect(message.isValidSignature(from: try chain.validated().signingKey))
    }

    @Test
    func `A bundle that doesn't start at the root is rejected`() throws {
        let (_, recorded) = try Self.recorded()
        var otherRoot = recorded
        otherRoot.root = try Self.generated().root
        var missingRoot = recorded
        missingRoot.bundle.removeFirst()
        var empty = recorded
        empty.bundle = []

        #expect(throws: NitroCertificateChain.ValidationError.untrustedRoot) { try otherRoot.validated() }
        #expect(throws: NitroCertificateChain.ValidationError.untrustedRoot) { try missingRoot.validated() }
        #expect(throws: NitroCertificateChain.ValidationError.untrustedRoot) { try empty.validated() }
    }

    @Test
    func `Certificates may start at most 300 seconds after the clock`() throws {
        var (_, chain) = try Self.recorded()
        let start = try Certificate(derEncoded: chain.certificate).notValidBefore

        chain.date = start - 300
        #expect(throws: Never.self) { try chain.validated() }
        chain.date = start - 301
        #expect(throws: NitroCertificateChain.ValidationError.outsideValidity) { try chain.validated() }
    }

    @Test
    func `Expired certificates are rejected`() throws {
        var (_, chain) = try Self.recorded()
        chain.date = try Certificate(derEncoded: chain.certificate).notValidAfter + 1

        #expect(throws: NitroCertificateChain.ValidationError.outsideValidity) { try chain.validated() }
    }

    @Test
    func `A bundle out of order is rejected`() throws {
        var (_, chain) = try Self.recorded()
        chain.bundle.swapAt(1, 2)

        #expect(throws: NitroCertificateChain.ValidationError.unsignedByIssuer) { try chain.validated() }
    }

    @Test
    func `A certificate with a changed signature is rejected`() throws {
        var (_, chain) = try Self.recorded()
        chain.certificate[chain.certificate.count - 1] ^= 0x01

        #expect(throws: NitroCertificateChain.ValidationError.unsignedByIssuer) { try chain.validated() }
    }

    @Test
    func `Bytes other than a certificate are rejected`() throws {
        var chain = try Self.generated()
        chain.certificate = [0x30, 0x00]

        #expect(throws: NitroCertificateChain.ValidationError.malformed) { try chain.validated() }
    }

    @Test
    func `A generated chain is valid`() throws {
        let chain = try Self.generated()

        #expect(throws: Never.self) { try chain.validated() }
    }

    @Test
    func `An issuer that isn't a certificate authority is rejected`() throws {
        let chain = try Self.generated(rootExtensions: Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(keyCertSign: true))
        })

        #expect(throws: NitroCertificateChain.ValidationError.unauthorizedIssuer) { try chain.validated() }
    }

    @Test
    func `An issuer that may not sign certificates is rejected`() throws {
        let chain = try Self.generated(rootExtensions: Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            Critical(KeyUsage(digitalSignature: true, cRLSign: true))
        })

        #expect(throws: NitroCertificateChain.ValidationError.unauthorizedIssuer) { try chain.validated() }
    }

    @Test
    func `An issuer's path length limits the authorities below it`() throws {
        let allowed = try Self.generated(rootExtensions: Self.authority(maxPathLength: 1), intermediates: 1)
        let exceeded = try Self.generated(rootExtensions: Self.authority(maxPathLength: 0), intermediates: 1)

        #expect(throws: Never.self) { try allowed.validated() }
        #expect(throws: NitroCertificateChain.ValidationError.unauthorizedIssuer) { try exceeded.validated() }
    }

    @Test
    func `A signer that may not make digital signatures is rejected`() throws {
        let chain = try Self.generated(leafExtensions: Certificate.Extensions { KeyUsage(keyEncipherment: true) })

        #expect(throws: NitroCertificateChain.ValidationError.unauthorizedSigner) { try chain.validated() }
    }

    @Test
    func `An unknown critical extension is rejected`() throws {
        let unknown = Certificate.Extension(oid: [1, 3, 6, 1, 4, 1, 99_999, 1], critical: true, value: [0x05, 0x00])
        let critical = try Self.generated(leafExtensions: Certificate.Extensions { unknown })
        let noncritical = try Self.generated(leafExtensions: Certificate.Extensions {
            Certificate.Extension(oid: unknown.oid, critical: false, value: unknown.value)
        })

        #expect(throws: NitroCertificateChain.ValidationError.unknownCriticalExtension) { try critical.validated() }
        #expect(throws: Never.self) { try noncritical.validated() }
    }

    @Test
    func `A certificate signed with another algorithm is rejected`() throws {
        let chain = try Self.generated(signatureAlgorithm: .ecdsaWithSHA256)

        #expect(throws: NitroCertificateChain.ValidationError.unsupportedAlgorithm) { try chain.validated() }
    }

    @Test
    func `A key other than P-384 is rejected`() throws {
        let chain = try Self.generated(leafKey: Certificate.PrivateKey(P256.Signing.PrivateKey()))

        #expect(throws: NitroCertificateChain.ValidationError.unsupportedAlgorithm) { try chain.validated() }
    }

    private static func recorded() throws -> (message: COSESign1, chain: Chain) {
        let recorded = try RecordedNitroAttestation.load()
        let message = try COSESign1(decoding: fixtureBytes(recorded.attestation.evidence.document))
        guard case .map(let document) = try CBOR(decoding: message.payload),
            case .bytes(let certificate)? = document[.text("certificate")],
            case .array(let items)? = document[.text("cabundle")]
        else { throw CBOR.ValidationError.malformed }
        let bundle = try items.map { item in
            guard case .bytes(let bytes) = item else { throw CBOR.ValidationError.malformed }
            return bytes
        }
        let date = Date(timeIntervalSince1970: TimeInterval(recorded.capturedAt))
        return (message, Chain(certificate: certificate, bundle: bundle, root: NitroCertificateChain.awsNitroEnclavesRoot, date: date))
    }

    private static func authority(maxPathLength: Int?) throws -> Certificate.Extensions {
        try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: maxPathLength))
            Critical(KeyUsage(keyCertSign: true))
        }
    }

    private static func generated(
        rootExtensions: Certificate.Extensions? = nil,
        intermediates: Int = 0,
        leafExtensions: Certificate.Extensions? = nil,
        leafKey: Certificate.PrivateKey = Certificate.PrivateKey(P384.Signing.PrivateKey()),
        signatureAlgorithm: Certificate.SignatureAlgorithm = .ecdsaWithSHA384
    ) throws -> Chain {
        let keys = (0...intermediates).map { _ in Certificate.PrivateKey(P384.Signing.PrivateKey()) } + [leafKey]
        let extensions = try [rootExtensions ?? authority(maxPathLength: nil)]
            + Array(repeating: authority(maxPathLength: nil), count: intermediates)
            + [leafExtensions ?? Certificate.Extensions { KeyUsage(digitalSignature: true) }]
        let certificates = try keys.indices.map { index in
            try issue(
                "level \(index)",
                publicKey: keys[index].publicKey,
                issuer: "level \(max(index - 1, 0))",
                issuerKey: keys[max(index - 1, 0)],
                signatureAlgorithm: signatureAlgorithm,
                extensions: extensions[index]
            )
        }
        return Chain(
            certificate: certificates[certificates.count - 1],
            bundle: Array(certificates.dropLast()),
            root: certificates[0],
            date: now
        )
    }

    private static func issue(
        _ subject: String,
        publicKey: Certificate.PublicKey,
        issuer: String,
        issuerKey: Certificate.PrivateKey,
        signatureAlgorithm: Certificate.SignatureAlgorithm,
        extensions: Certificate.Extensions
    ) throws -> [UInt8] {
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: publicKey,
            notValidBefore: now - 3_600,
            notValidAfter: now + 3_600,
            issuer: DistinguishedName { CommonName(issuer) },
            subject: DistinguishedName { CommonName(subject) },
            signatureAlgorithm: signatureAlgorithm,
            extensions: extensions,
            issuerPrivateKey: issuerKey
        )
        return try certificate.serializeAsPEM().derBytes
    }
}
