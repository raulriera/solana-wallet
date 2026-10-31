import Encoding
import Foundation
import Testing
@testable import Attestation

struct NitroCertificateTests {
    @Test(arguments: try NitroCertificateFixtures.load().certificates)
    func `Certificates from OpenSSL decode into their fields`(fixture: NitroCertificateFixtures.Certificate) throws {
        let certificate = try NitroCertificate(decoding: fixtureBytes(fixture.der))

        #expect(certificate.tbsCertificateBytes == (try fixtureBytes(fixture.tbsCertificate)))
        #expect(certificate.tbsSignatureAlgorithm == (try fixtureBytes(fixture.tbsSignatureAlgorithm)))
        #expect(certificate.issuer == (try fixtureBytes(fixture.issuer)))
        #expect(certificate.subject == (try fixtureBytes(fixture.subject)))
        #expect(certificate.publicKeyAlgorithm == (try fixtureBytes(fixture.publicKeyAlgorithm)))
        #expect(certificate.publicKey == (try fixtureBytes(fixture.publicKey)))
        #expect(certificate.signatureAlgorithm == (try fixtureBytes(fixture.signatureAlgorithm)))
        #expect(certificate.signature == (try fixtureBytes(fixture.signature)))
        #expect(
            certificate.extensions
                == (try fixture.extensions.map {
                    NitroCertificate.Extension(
                        oid: try fixtureBytes($0.oid),
                        isCritical: $0.critical,
                        value: try fixtureBytes($0.value)
                    )
                })
        )
    }

    @Test(arguments: try NitroCertificateFixtures.load().certificates)
    func `Certificates from OpenSSL decode the validity and constraints OpenSSL reads`(
        fixture: NitroCertificateFixtures.Certificate
    ) throws {
        let certificate = try NitroCertificate(decoding: fixtureBytes(fixture.der))

        #expect(NitroCertificateFixtures.Summary(certificate) == fixture.summary)
    }

    @Test
    func `The recorded AWS certificates decode the validity and constraints OpenSSL reads`() throws {
        let (_, certificate, bundle) = try RecordedNitroAttestation.load().decoded()

        let decoded = try ([certificate] + bundle).map(NitroCertificate.init(decoding:))

        #expect(decoded.map(NitroCertificateFixtures.Summary.init) == (try NitroCertificateFixtures.load().recorded))
    }

    @Test
    func `UTCTime years below 50 are in the 2000s and GeneralizedTime holds years from 2050`() throws {
        let fixtures = try NitroCertificateFixtures.load()

        let utcTime = try NitroCertificate(decoding: fixtures.bytes(of: "time-utc"))
        let generalizedTime = try NitroCertificate(decoding: fixtures.bytes(of: "time-generalized"))

        #expect(utcTime.notValidBefore == (try Date("1950-01-01T00:00:00Z", strategy: .iso8601)))
        #expect(utcTime.notValidAfter == (try Date("2049-12-31T23:59:59Z", strategy: .iso8601)))
        #expect(generalizedTime.notValidBefore == (try Date("2024-02-29T12:00:00Z", strategy: .iso8601)))
        #expect(generalizedTime.notValidAfter == (try Date("9999-12-31T23:59:59Z", strategy: .iso8601)))
    }

    @Test(arguments: try NitroCertificateFixtures.load().rejections.filter { $0.rule == .notDER })
    func `Certificates and extension values that aren't DER are rejected`(
        rejection: NitroCertificateFixtures.Rejection
    ) throws {
        let bytes = try fixtureBytes(rejection.der)

        #expect(throws: DER.ValidationError.self) { try NitroCertificate(decoding: bytes) }
    }

    @Test(arguments: try NitroCertificateFixtures.load().rejections.filter { $0.rule != .notDER })
    func `Certificates that break a DER or RFC 5280 rule are rejected with that rule's error`(
        rejection: NitroCertificateFixtures.Rejection
    ) throws {
        let bytes = try fixtureBytes(rejection.der)
        let error = try #require(rejection.rule.error)

        #expect(throws: error) { try NitroCertificate(decoding: bytes) }
    }
}
