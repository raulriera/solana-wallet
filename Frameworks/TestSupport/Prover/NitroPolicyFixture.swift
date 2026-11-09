import Foundation
import Testing
@testable import Attestation

struct NitroPolicyFixture: Decodable, Sendable {
    let platform: String
    let measurements: [Measurement]
    let gpu: String
    let maximumAge: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case platform
        case measurements
        case gpu
        case maximumAge = "max_age_secs"
    }

    struct Measurement: Decodable, Sendable {
        let pcr0: String
        let pcr1: String
        let pcr2: String
    }

    static func deployment(named name: String) throws -> Self {
        let file: [String: Self] = try fixture(named: name)
        return try #require(file["deployment"])
    }

    func policy(root: [UInt8]) throws -> NitroPolicy {
        NitroPolicy(
            measurements: try measurements.map { measurement in
                NitroPolicy.Measurement(
                    pcr0: try fixtureBytes(measurement.pcr0),
                    pcr1: try fixtureBytes(measurement.pcr1),
                    pcr2: try fixtureBytes(measurement.pcr2)
                )
            },
            publicKey: nil,
            root: root,
            maximumAge: maximumAge
        )
    }
}
