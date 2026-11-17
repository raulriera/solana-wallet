import CryptoKit
import Foundation
import Testing
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

    @Test
    func `The recorded chain yields the key that signs the document`() throws {
        let (message, chain) = try Self.recorded()

        #expect(message.isValidSignature(from: try chain.validated().signingKey))
    }

    @Test
    func `A bundle that doesn't start at the root is rejected`() throws {
        let (_, recorded) = try Self.recorded()
        var otherRoot = recorded
        otherRoot.root = try Self.generated("leaf", issuedThrough: ["root"]).root
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
        let start = Date(timeIntervalSince1970: try Self.recordedSigner().notValidBefore)

        chain.date = start - 300
        #expect(throws: Never.self) { try chain.validated() }
        chain.date = start - 301
        #expect(throws: NitroCertificateChain.ValidationError.outsideValidity) { try chain.validated() }
    }

    @Test
    func `Expired certificates are rejected`() throws {
        var (_, chain) = try Self.recorded()
        chain.date = Date(timeIntervalSince1970: try Self.recordedSigner().notValidAfter + 1)

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
        var chain = try Self.generated("leaf", issuedThrough: ["root"])
        chain.certificate = [0x30, 0x00]

        #expect(throws: NitroCertificateChain.ValidationError.malformed) { try chain.validated() }
    }

    @Test(arguments: ["leaf-off-curve-key", "leaf-unparsable-signature"])
    func `A P-384 key or ECDSA signature that CryptoKit can't read is rejected`(signer: String) throws {
        let chain = try Self.generated(signer, issuedThrough: ["root"])

        #expect(throws: NitroCertificateChain.ValidationError.malformed) { try chain.validated() }
    }

    @Test(arguments: [
        ("leaf", ["root"]),
        ("leaf-without-extensions", ["root"]),
        ("leaf-below-intermediate", ["root", "intermediate"]),
    ])
    func `A generated chain yields its signer's key`(signer: String, bundle: [String]) throws {
        let chain = try Self.generated(signer, issuedThrough: bundle)
        let key = try fixtureBytes(NitroCertificateFixtures.load().certificate(named: signer).publicKey)

        #expect(Array(try chain.validated().signingKey.x963Representation) == key)
    }

    @Test(arguments: ["root-not-authority", "root-without-basic-constraints", "root-without-certificate-signing"])
    func `An issuer that isn't a certificate authority or may not sign certificates is rejected`(
        issuer: String
    ) throws {
        let chain = try Self.generated("leaf", issuedThrough: [issuer])

        #expect(throws: NitroCertificateChain.ValidationError.unauthorizedIssuer) { try chain.validated() }
    }

    @Test
    func `An issuer's path length limits the authorities below it`() throws {
        let signer = "leaf-below-intermediate"
        let allowed = try Self.generated(signer, issuedThrough: ["root-path-length-1", "intermediate"])
        let exceeded = try Self.generated(signer, issuedThrough: ["root-path-length-0", "intermediate"])

        #expect(throws: Never.self) { try allowed.validated() }
        #expect(throws: NitroCertificateChain.ValidationError.unauthorizedIssuer) { try exceeded.validated() }
    }

    @Test
    func `A signer that may not make digital signatures is rejected`() throws {
        let chain = try Self.generated("leaf-key-encipherment", issuedThrough: ["root"])

        #expect(throws: NitroCertificateChain.ValidationError.unauthorizedSigner) { try chain.validated() }
    }

    @Test
    func `An unknown critical extension is rejected`() throws {
        let critical = try Self.generated("leaf-unknown-critical", issuedThrough: ["root"])
        let noncritical = try Self.generated("leaf-unknown-noncritical", issuedThrough: ["root"])

        #expect(throws: NitroCertificateChain.ValidationError.unknownCriticalExtension) { try critical.validated() }
        #expect(throws: Never.self) { try noncritical.validated() }
    }

    @Test(arguments: [
        ("leaf-sha256", "root"),
        ("leaf-tbs-sha256", "root"),
        ("leaf-rsa-signed", "rsa-root"),
        ("leaf-p256", "root"),
        ("leaf-rsa", "root"),
        ("leaf-ed25519", "root"),
    ])
    func `A certificate with a key or signature other than P-384 ECDSA with SHA-384 is rejected`(
        signer: String,
        issuer: String
    ) throws {
        let chain = try Self.generated(signer, issuedThrough: [issuer])

        #expect(throws: NitroCertificateChain.ValidationError.unsupportedAlgorithm) { try chain.validated() }
    }

    @Test
    func `An issuer name that differs only in its string type is rejected`() throws {
        let chain = try Self.generated("leaf-printable-issuer", issuedThrough: ["root"])

        #expect(throws: NitroCertificateChain.ValidationError.unsignedByIssuer) { try chain.validated() }
    }

    private static func recorded() throws -> (message: COSESign1, chain: Chain) {
        let recorded = try RecordedNitroAttestation.load(named: "RecordedDevnetNitroAttestation")
        let (message, certificate, bundle) = try recorded.decoded()
        let chain = Chain(
            certificate: certificate,
            bundle: bundle,
            root: NitroCertificateChain.awsNitroEnclavesRoot,
            date: recorded.capturedDate
        )
        return (message, chain)
    }

    private static func recordedSigner() throws -> NitroCertificateFixtures.Summary {
        try #require(NitroCertificateFixtures.load().recorded.first)
    }

    private static func generated(_ signer: String, issuedThrough bundle: [String]) throws -> Chain {
        let fixtures = try NitroCertificateFixtures.load()
        let bundle = try bundle.map(fixtures.bytes(of:))
        return Chain(
            certificate: try fixtures.bytes(of: signer),
            bundle: bundle,
            root: try #require(bundle.first),
            date: Date(timeIntervalSince1970: TimeInterval(fixtures.date))
        )
    }
}
