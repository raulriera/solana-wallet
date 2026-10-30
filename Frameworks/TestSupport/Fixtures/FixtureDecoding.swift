import Foundation
import Testing

func fixtureBytes(_ hex: String) throws -> [UInt8] {
    let characters = Array(hex)
    try #require(characters.count.isMultiple(of: 2))
    return try stride(from: 0, to: characters.count, by: 2).map { index in
        try #require(UInt8(String(characters[index...index + 1]), radix: 16))
    }
}

func fixture<Value: Decodable>(named name: String) throws -> Value {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
}

private final class FixtureBundle: NSObject {}
