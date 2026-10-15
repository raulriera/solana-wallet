import Foundation
import Testing

/// Decodes hexadecimal fixture bytes.
///
/// - Parameter hex: An even number of hexadecimal digits from a public test vector.
/// - Returns: The bytes in their original order.
/// - Throws: A test failure if the fixture is malformed.
func fixtureBytes(_ hex: String) throws -> [UInt8] {
    let characters = Array(hex)
    try #require(characters.count.isMultiple(of: 2))
    return try stride(from: 0, to: characters.count, by: 2).map { index in
        try #require(UInt8(String(characters[index...index + 1]), radix: 16))
    }
}

/// Decodes a JSON fixture from the test bundle that compiles this file.
///
/// - Parameter name: The resource name, without its `json` extension.
/// - Returns: The decoded fixture.
/// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
func fixture<Value: Decodable>(named name: String) throws -> Value {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
}

/// Identifies the test bundle that compiles these helpers, which also contains its fixtures.
private final class FixtureBundle: NSObject {}
