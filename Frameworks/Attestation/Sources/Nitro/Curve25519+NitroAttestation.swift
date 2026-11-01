public import CryptoKit
public import Foundation

extension Curve25519.KeyAgreement.PublicKey {
    /// The domain that separates report data from the prover protocol's other hashes.
    private static let reportDomain = Array("zolana/prover-tee/v1/report".utf8)

    /// The GPU digest of an attestation without a GPU verdict.
    private static let absentGPUDigest = [UInt8](repeating: 0, count: 32)

    private static let nonceByteCount = 32

    /// Creates an HPKE key from its raw representation once an AWS Nitro attestation document binds it to the
    /// client's nonce under a policy.
    ///
    /// - Parameters:
    ///   - rawRepresentation: The 32-byte key the prover claims.
    ///   - bytes: The COSE_Sign1 attestation document the prover returned with the key.
    ///   - nonce: The 32-byte nonce the client sent with the attestation request.
    ///   - policy: The deployment the prover must run.
    ///   - date: The time the document's certificates must be valid at.
    /// - Throws: `CryptoKitError.incorrectKeySize` unless the key has 32 bytes,
    ///   `CryptoKitError.incorrectParameterSize` unless the nonce has 32 bytes, or a ``NitroPolicy/ValidationError``
    ///   for a document that fails a check.
    public init(
        rawRepresentation: some ContiguousBytes,
        attestedBy bytes: some DataProtocol,
        nonce: some DataProtocol,
        policy: NitroPolicy,
        at date: Date
    ) throws {
        let key = rawRepresentation.withUnsafeBytes { [UInt8]($0) }
        let nonce = [UInt8](nonce)
        try self.init(rawRepresentation: key)
        guard nonce.count == Self.nonceByteCount else { throw CryptoKitError.incorrectParameterSize }
        let message: COSESign1
        do {
            message = try COSESign1(decoding: [UInt8](bytes))
        } catch COSESign1.ValidationError.unsupportedAlgorithm {
            throw NitroPolicy.ValidationError.unsupportedAlgorithm
        } catch {
            throw NitroPolicy.ValidationError.malformed
        }
        let document = try NitroAttestationDocument(decoding: message.payload)
        guard
            let chain = try? NitroCertificateChain(
                certificate: document.certificate,
                bundle: document.bundle,
                root: policy.root,
                at: date
            )
        else { throw NitroPolicy.ValidationError.untrustedCertificateChain }
        guard message.isValidSignature(from: chain.signingKey) else {
            throw NitroPolicy.ValidationError.invalidSignature
        }
        try policy.validate(document.measurement, publicKey: key)
        guard document.publicKey == key else { throw NitroPolicy.ValidationError.publicKeyMismatch }
        guard document.nonce == nonce else { throw NitroPolicy.ValidationError.nonceMismatch }
        guard document.userData == reportData(nonce: nonce) else {
            throw NitroPolicy.ValidationError.reportDataMismatch
        }
    }

    /// Computes the report data that binds the key to a nonce with no GPU verdict.
    ///
    /// - Parameter nonce: The nonce the client sent with the attestation request.
    /// - Returns: The 64-byte SHA-512 digest of the domain, the nonce, the key, and the absent GPU digest.
    func reportData(nonce: [UInt8]) -> [UInt8] {
        Array(SHA512.hash(data: Self.reportDomain + nonce + rawRepresentation + Self.absentGPUDigest))
    }
}
