import Foundation
import Testing
@testable import Attestation

struct NitroCertificateFixtures: Decodable, Sendable {
    let date: Int
    let certificates: [Certificate]
    let rejections: [Rejection]
    let recorded: [Summary]

    struct Certificate: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let der: String
        let tbsCertificate: String
        let tbsSignatureAlgorithm: String
        let issuer: String
        let subject: String
        let publicKeyAlgorithm: String
        let publicKey: String
        let extensions: [Extension]
        let signatureAlgorithm: String
        let signature: String
        let summary: Summary

        var testDescription: String { name }
    }

    struct Extension: Decodable, Sendable {
        let oid: String
        let critical: Bool
        let value: String
    }

    struct Summary: Decodable, Equatable, Sendable {
        let notValidBefore: TimeInterval
        let notValidAfter: TimeInterval
        let basicConstraints: BasicConstraints?
        let keyUsage: KeyUsage?
    }

    struct BasicConstraints: Decodable, Equatable, Sendable {
        let certificateAuthority: Bool
        let maxPathLength: Int?
    }

    struct KeyUsage: Decodable, Equatable, Sendable {
        let digitalSignature: Bool
        let keyCertSign: Bool
    }

    struct Rejection: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let rule: Rule
        let der: String

        var testDescription: String { name }
    }

    enum Rule: String, Decodable, Sendable {
        case notDER
        case malformed
        case unsupportedVersion
        case invalidInteger
        case invalidBoolean
        case invalidBitString
        case invalidObjectIdentifier
        case invalidTime
        case duplicateExtension

        var error: NitroCertificate.ValidationError? {
            switch self {
            case .notDER: nil
            case .malformed: .malformed
            case .unsupportedVersion: .unsupportedVersion
            case .invalidInteger: .invalidInteger
            case .invalidBoolean: .invalidBoolean
            case .invalidBitString: .invalidBitString
            case .invalidObjectIdentifier: .invalidObjectIdentifier
            case .invalidTime: .invalidTime
            case .duplicateExtension: .duplicateExtension
            }
        }
    }

    private static let decoded = Result { try fixture(named: "NitroCertificateFixtures") as Self }

    static func load() throws -> Self {
        try decoded.get()
    }

    func certificate(named name: String) throws -> Certificate {
        try #require(certificates.first { $0.name == name })
    }

    func bytes(of name: String) throws -> [UInt8] {
        try fixtureBytes(certificate(named: name).der)
    }
}

extension NitroCertificateFixtures.Summary {
    init(_ certificate: NitroCertificate) {
        self.init(
            notValidBefore: certificate.notValidBefore.timeIntervalSince1970,
            notValidAfter: certificate.notValidAfter.timeIntervalSince1970,
            basicConstraints: certificate.basicConstraints.map(NitroCertificateFixtures.BasicConstraints.init),
            keyUsage: certificate.keyUsage.map {
                NitroCertificateFixtures.KeyUsage(digitalSignature: $0.digitalSignature, keyCertSign: $0.keyCertSign)
            }
        )
    }
}

extension NitroCertificateFixtures.BasicConstraints {
    init(_ constraints: NitroCertificate.BasicConstraints) {
        switch constraints {
        case .isCertificateAuthority(let maxPathLength):
            self.init(certificateAuthority: true, maxPathLength: maxPathLength)
        case .notCertificateAuthority:
            self.init(certificateAuthority: false, maxPathLength: nil)
        }
    }
}
