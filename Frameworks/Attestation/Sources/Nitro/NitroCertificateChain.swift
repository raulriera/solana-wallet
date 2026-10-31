import CryptoKit
import Foundation
import SwiftASN1
import X509

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

    private static let knownCriticalExtensions: [ASN1ObjectIdentifier] = [
        .X509ExtensionID.basicConstraints,
        .X509ExtensionID.keyUsage,
    ]

    /// The DER of the ecdsa-with-SHA384 algorithm identifier.
    private static let ecdsaWithSHA384: [UInt8] = [0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03]

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
        do {
            let path = try ([certificate] + bundle.reversed()).map { try Certificate(derEncoded: $0) }
            signingKey = try path.map { try Self.validatedKey(of: $0, at: date) }[0]
            for (depth, (child, issuer)) in zip(path, path.dropFirst()).enumerated().reversed() {
                guard child.issuer == issuer.subject, issuer.publicKey.isValidSignature(child.signature, for: child)
                else { throw ValidationError.unsignedByIssuer }
                guard case .isCertificateAuthority(let maxPathLength)? = try issuer.extensions.basicConstraints,
                    maxPathLength.map({ $0 >= depth }) ?? true,
                    try issuer.extensions.keyUsage?.keyCertSign ?? true
                else { throw ValidationError.unauthorizedIssuer }
            }
            guard try path[0].extensions.keyUsage?.digitalSignature ?? true else {
                throw ValidationError.unauthorizedSigner
            }
        } catch let error as ValidationError {
            throw error
        } catch {
            throw ValidationError.malformed
        }
    }

    /// Checks a certificate on its own and reads its key.
    ///
    /// - Parameters:
    ///   - certificate: The certificate to check.
    ///   - date: The time the certificate must be valid at.
    /// - Returns: The certificate's P-384 key.
    /// - Throws: ``ValidationError/outsideValidity`` for a certificate not valid at `date`,
    ///   ``ValidationError/unknownCriticalExtension`` for a critical extension other than basic constraints and
    ///   key usage, ``ValidationError/unsupportedAlgorithm`` for a signature other than ecdsa-with-SHA384 or a
    ///   key other than P-384, or an error for a certificate whose signed part doesn't parse.
    private static func validatedKey(of certificate: Certificate, at date: Date) throws -> P384.Signing.PublicKey {
        guard certificate.notValidBefore <= date + notBeforeTolerance, date <= certificate.notValidAfter else {
            throw ValidationError.outsideValidity
        }
        guard certificate.extensions.allSatisfy({ !$0.critical || knownCriticalExtensions.contains($0.oid) }) else {
            throw ValidationError.unknownCriticalExtension
        }
        guard certificate.signatureAlgorithm == .ecdsaWithSHA384,
            case .constructed(let fields) = try DER.parse(certificate.tbsCertificateBytes).content,
            fields.first(where: { $0.identifier == .sequence })?.encodedBytes.elementsEqual(ecdsaWithSHA384) == true,
            let key = P384.Signing.PublicKey(certificate.publicKey)
        else { throw ValidationError.unsupportedAlgorithm }
        return key
    }
}
