import Encoding
import Foundation
import Testing

func fixtureBytes(_ hex: String) throws -> [UInt8] {
    try #require(Hex.decode(hex))
}

func fixture<Value: Decodable>(named name: String) throws -> Value {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
}

private final class FixtureBundle: NSObject {}
