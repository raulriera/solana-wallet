import CryptoKit
import Foundation

/// A certificate chain that carries an AWS Nitro attestation document's signing key from a trusted root.
struct NitroCertificateChain: Sendable {
    /// An error that rejects a certificate chain.
    enum ValidationError: Error, Equatable {
        case malformed
        case untrustedRoot
        case outsideValidity
        case unknownCriticalExtension
        case unsupportedAlgorithm
        case unsignedByIssuer
        case unauthorizedIssuer
        case unauthorizedSigner
    }

    /// The time a certificate's start of validity may lead the clock, in seconds.
    private static let notBeforeTolerance: TimeInterval = 300

    private static let knownCriticalExtensions = [
        NitroCertificate.Extension.basicConstraintsOID,
        NitroCertificate.Extension.keyUsageOID,
    ]

    /// The DER of the ecdsa-with-SHA384 algorithm identifier.
    private static let ecdsaWithSHA384: [UInt8] = [0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03]

    /// The DER of the algorithm identifier of an elliptic curve key on P-384, id-ecPublicKey with secp384r1.
    private static let p384PublicKey: [UInt8] = [
        0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22,
    ]

    /// The key of the certificate that signs the document.
    let signingKey: P384.Signing.PublicKey

    /// Validates the chain from a document's certificate through its bundle, read in reverse, to a root.
    ///
    /// - Parameters:
    ///   - certificate: The DER of the certificate that signs the document.
    ///   - bundle: The DER of the issuing certificates, from the root down.
    ///   - root: The DER of the trusted root, which the bundle must start with.
    ///   - date: The time every certificate must be valid at.
    /// - Throws: A ``ValidationError`` for a chain that fails a check.
    init(certificate: [UInt8], bundle: [[UInt8]], root: [UInt8], at date: Date) throws {
        guard bundle.first == root else { throw ValidationError.untrustedRoot }
        guard let path = try? ([certificate] + bundle.reversed()).map(NitroCertificate.init(decoding:)) else {
            throw ValidationError.malformed
        }
        let signed = try path.map { try Self.validated($0, at: date) }
        for depth in path.indices.dropLast().reversed() {
            let (child, issuer) = (path[depth], path[depth + 1])
            guard child.issuer == issuer.subject,
                signed[depth + 1].key.isValidSignature(signed[depth].signature, for: child.tbsCertificateBytes)
            else { throw ValidationError.unsignedByIssuer }
            guard case .isCertificateAuthority(let maxPathLength)? = issuer.basicConstraints,
                maxPathLength.map({ $0 >= depth }) ?? true,
                issuer.keyUsage?.keyCertSign ?? true
            else { throw ValidationError.unauthorizedIssuer }
        }
        guard path[0].keyUsage?.digitalSignature ?? true else { throw ValidationError.unauthorizedSigner }
        signingKey = signed[0].key
    }

    /// Checks a certificate on its own and reads its key and signature.
    ///
    /// - Parameters:
    ///   - certificate: The certificate to check.
    ///   - date: The time the certificate must be valid at.
    /// - Returns: The certificate's P-384 key and its ECDSA signature.
    /// - Throws: ``ValidationError/outsideValidity`` for a certificate not valid at `date`,
    ///   ``ValidationError/unknownCriticalExtension`` for a critical extension other than basic constraints and
    ///   key usage, ``ValidationError/unsupportedAlgorithm`` for a signature other than ecdsa-with-SHA384 or a
    ///   key other than P-384, or ``ValidationError/malformed`` for a key or signature that CryptoKit can't read.
    private static func validated(
        _ certificate: NitroCertificate,
        at date: Date
    ) throws -> (key: P384.Signing.PublicKey, signature: P384.Signing.ECDSASignature) {
        guard certificate.notValidBefore <= date + notBeforeTolerance, date <= certificate.notValidAfter else {
            throw ValidationError.outsideValidity
        }
        guard certificate.extensions.allSatisfy({ !$0.isCritical || knownCriticalExtensions.contains($0.oid) }) else {
            throw ValidationError.unknownCriticalExtension
        }
        guard certificate.signatureAlgorithm == ecdsaWithSHA384, certificate.tbsSignatureAlgorithm == ecdsaWithSHA384,
            certificate.publicKeyAlgorithm == p384PublicKey
        else { throw ValidationError.unsupportedAlgorithm }
        guard let key = try? P384.Signing.PublicKey(x963Representation: certificate.publicKey),
            let signature = try? P384.Signing.ECDSASignature(derRepresentation: certificate.signature)
        else { throw ValidationError.malformed }
        return (key, signature)
    }
}
