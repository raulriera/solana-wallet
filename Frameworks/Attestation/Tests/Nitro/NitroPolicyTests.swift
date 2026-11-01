import Testing
@testable import Attestation

struct NitroPolicyTests {
    private static let other = [UInt8](repeating: 0x0f, count: 48)

    @Test(arguments: [(NitroPolicy.devnet, "DevnetNitroPolicy"), (.mainnet, "MainnetNitroPolicy")])
    func `Pinned policies match their deployment files`(policy: NitroPolicy, file: String) throws {
        let deployment = try NitroPolicyFixture.deployment(named: file)
        let pinned = try deployment.policy(root: NitroCertificateChain.awsNitroEnclavesRoot)

        #expect(deployment.platform == "aws-nitro")
        #expect(deployment.gpu == "optional")
        #expect(policy.measurements == pinned.measurements)
        #expect(policy.hpkePublicKey == pinned.hpkePublicKey)
        #expect(policy.root == pinned.root)
    }

    @Test(arguments: [0, 1, 2])
    func `A measurement that differs in any PCR is rejected`(index: Int) throws {
        let policy = try NitroCBORCases.load().trustedPolicy()
        let allowed = try #require(policy.measurements.first)
        let measurement = NitroPolicy.Measurement(
            pcr0: index == 0 ? Self.other : allowed.pcr0,
            pcr1: index == 1 ? Self.other : allowed.pcr1,
            pcr2: index == 2 ? Self.other : allowed.pcr2
        )

        #expect(throws: Never.self) { try policy.validate(allowed, publicKey: []) }
        #expect(throws: NitroPolicy.ValidationError.unexpectedMeasurement) {
            try policy.validate(measurement, publicKey: [])
        }
    }

    @Test
    func `A policy without measurements rejects every measurement`() throws {
        let allowed = try #require(NitroCBORCases.load().trustedPolicy().measurements.first)
        let policy = NitroPolicy(measurements: [], hpkePublicKey: nil, root: [])

        #expect(throws: NitroPolicy.ValidationError.unexpectedMeasurement) {
            try policy.validate(allowed, publicKey: [])
        }
    }

    @Test
    func `A policy that pins a key admits only that key`() throws {
        let cases = try NitroCBORCases.load()
        let key = try fixtureBytes(cases.hpkePublicKey)
        let allowed = try #require(cases.trustedPolicy().measurements.first)
        let policy = NitroPolicy(measurements: [allowed], hpkePublicKey: key, root: [])

        #expect(throws: Never.self) { try policy.validate(allowed, publicKey: key) }
        #expect(throws: NitroPolicy.ValidationError.unexpectedPublicKey) {
            try policy.validate(allowed, publicKey: Array(Self.other.prefix(32)))
        }
    }
}
