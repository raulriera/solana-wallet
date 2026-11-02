public import Foundation

/// The AWS Nitro Enclaves images and public key that an attestation document must match, and how long a passed
/// attestation is reused.
public struct NitroPolicy: Sendable {
    /// An error that rejects an AWS Nitro attestation under a policy.
    enum ValidationError: Error, Equatable {
        /// A message or document outside the strict CBOR subset, or with fields that are missing, of other types, or
        /// out of range.
        case malformed
        /// A message whose protected header doesn't name ES384.
        case unsupportedAlgorithm
        /// A certificate and bundle that don't form a valid chain from the policy's root at the time.
        case untrustedCertificateChain
        /// A message that the document's certificate didn't sign.
        case invalidSignature
        /// PCRs of a digest other than SHA-384.
        case unsupportedDigest
        /// A zero PCR0, which a debug enclave reports.
        case debugEnclave
        /// PCR0 through PCR2 that match none of the policy's measurements.
        case unexpectedMeasurement
        /// A claimed key other than the one the policy pins.
        case unexpectedPublicKey
        /// A document whose public key isn't the claimed key.
        case publicKeyMismatch
        /// A document whose nonce isn't the client's.
        case nonceMismatch
        /// A document whose user data isn't the caller's.
        case userDataMismatch
    }

    /// PCR0 through PCR2 of an enclave image.
    public struct Measurement: Equatable, Sendable {
        let pcr0: [UInt8]
        let pcr1: [UInt8]
        let pcr2: [UInt8]

        /// Creates a measurement from an enclave image's registers.
        ///
        /// - Parameters:
        ///   - pcr0: The 48-byte SHA-384 measurement of the enclave image file.
        ///   - pcr1: The 48-byte SHA-384 measurement of the kernel and boot ramfs.
        ///   - pcr2: The 48-byte SHA-384 measurement of the application.
        public init(pcr0: [UInt8], pcr1: [UInt8], pcr2: [UInt8]) {
            self.pcr0 = pcr0
            self.pcr1 = pcr1
            self.pcr2 = pcr2
        }
    }

    /// The enclave images the policy allows.
    let measurements: [Measurement]

    /// The only public key the policy allows, or `nil` to allow any key.
    let publicKey: [UInt8]?

    /// The DER of the root that a document's certificate chain must start at.
    let root: [UInt8]

    /// How long a passed attestation is reused, in seconds.
    public let maximumAge: TimeInterval

    /// Checks an enclave's measurement and a claimed public key against the policy's pins.
    ///
    /// - Parameters:
    ///   - measurement: The PCR0 through PCR2 that a verified document reports.
    ///   - publicKey: The public key the enclave claims.
    /// - Throws: ``ValidationError/unexpectedMeasurement`` for a measurement other than the policy's, or
    ///   ``ValidationError/unexpectedPublicKey`` for a key other than the pinned one.
    func validate(_ measurement: Measurement, publicKey: [UInt8]) throws {
        guard measurements.contains(measurement) else { throw ValidationError.unexpectedMeasurement }
        if let pinned = self.publicKey, pinned != publicKey { throw ValidationError.unexpectedPublicKey }
    }
}

extension NitroPolicy {
    /// Creates a policy whose certificate chains start at the AWS Nitro Enclaves root.
    ///
    /// - Parameters:
    ///   - measurements: The enclave images the policy allows.
    ///   - publicKey: The only public key the policy allows, or `nil` to allow any key.
    ///   - maximumAge: How long a passed attestation is reused, in seconds.
    public init(measurements: [Measurement], publicKey: [UInt8]?, maximumAge: TimeInterval) {
        self.init(
            measurements: measurements,
            publicKey: publicKey,
            root: NitroCertificateChain.awsNitroEnclavesRoot,
            maximumAge: maximumAge
        )
    }
}
