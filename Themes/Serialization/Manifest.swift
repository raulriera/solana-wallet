import Foundation
import CoreFoundation

/// The internal version-one manifest representation.
struct Manifest: Sendable {
    let id: UUID
    let name: String
    let colors: [Appearance: [Role: Color]]
    let assets: [String: String]

    /// Creates manifest values for an imported or exported pack.
    /// - Parameters:
    ///   - id: The stable theme identity.
    ///   - name: A validated display name.
    ///   - colors: Sparse overrides or complete export values.
    ///   - assets: Named package-relative image paths.
    init(id: UUID, name: String, colors: [Appearance: [Role: Color]], assets: [String: String]) {
        self.id = id
        self.name = name
        self.colors = colors
        self.assets = assets
    }

    /// Decodes a manifest while rejecting unknown fields and explicit null values.
    /// - Parameter data: UTF-8 JSON manifest bytes.
    /// - Returns: Validated metadata, color overrides, and asset declarations.
    /// - Throws: A field-specific validation error.
    static func decode(_ data: Data) throws -> Manifest {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ValidationError(path: "manifest.json", reason: "Expected valid JSON.")
        }
        let root = try object(json, at: "manifest.json", keys: ["version", "id", "name", "tokens", "assets"])
        guard let version = root["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue.rounded(.towardZero) == version.doubleValue else {
            throw ValidationError(path: "version", reason: "Expected an integer.")
        }
        guard version == 1 else {
            throw ValidationError(path: "version", reason: "Unsupported format version \(version); expected 1.")
        }
        let identifier = try string(root["id"], at: "id")
        guard let id = UUID(uuidString: identifier) else {
            throw ValidationError(path: "id", reason: "Expected a UUID string.")
        }
        let name = try string(root["name"], at: "name")
        try validateName(name)
        var colors: [Appearance: [Role: Color]] = [:]
        if let suppliedTokens = root["tokens"] {
            let tokens = try object(suppliedTokens, at: "tokens", keys: ["colors"])
            if let suppliedColors = tokens["colors"] {
                let appearances = try object(suppliedColors, at: "tokens.colors",
                                             keys: Appearance.allCases.map(\.rawValue))
                for appearance in Appearance.allCases {
                    guard let suppliedPalette = appearances[appearance.rawValue] else { continue }
                    let path = "tokens.colors.\(appearance.rawValue)"
                    let palette = try object(suppliedPalette, at: path, keys: Role.allCases.map(\.rawValue))
                    var values: [Role: Color] = [:]
                    for role in Role.allCases {
                        if let value = palette[role.rawValue] {
                            values[role] = try color(value, at: "\(path).\(role.rawValue)")
                        }
                    }
                    colors[appearance] = values
                }
            }
        }
        var assets: [String: String] = [:]
        if let suppliedAssets = root["assets"] {
            let declarations = try object(suppliedAssets, at: "assets")
            for key in declarations.keys.sorted() {
                assets[key] = try string(declarations[key], at: "assets.\(key)")
            }
        }
        return Manifest(id: id, name: name, colors: colors, assets: assets)
    }

    /// Serializes a manifest without resolving symbolic system colors.
    /// - Returns: Deterministically ordered, readable JSON.
    /// - Throws: A JSON serialization error.
    func encode() throws -> Data {
        let palettes = Dictionary(uniqueKeysWithValues: colors.map { appearance, palette in
            (appearance.rawValue, Dictionary(uniqueKeysWithValues: palette.map { role, value in
                let encoded: [String: String]
                switch value {
                case .system(let name): encoded = ["system": name.rawValue]
                case .srgb(let red, let green, let blue):
                    encoded = ["srgb": String(format: "#%02X%02X%02X", red, green, blue)]
                }
                return (role.rawValue, encoded)
            }))
        })
        let json: [String: Any] = ["version": 1, "id": id.uuidString, "name": name,
                                   "tokens": ["colors": palettes], "assets": assets]
        var data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    /// Rejects display names containing no visible characters.
    /// - Parameter name: The supplied display name.
    /// - Throws: A validation error when the name is empty or whitespace.
    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError(path: "name", reason: "Expected a nonempty display name.")
        }
    }

    /// Reads an object and optionally checks its supported keys.
    /// - Parameters:
    ///   - value: A decoded JSON value.
    ///   - path: Its manifest location.
    ///   - keys: Allowed field names, or nil for an arbitrary-name map.
    /// - Returns: A JSON object.
    /// - Throws: A validation error for a wrong type or unknown key.
    private static func object(_ value: Any, at path: String, keys: [String]? = nil) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw ValidationError(path: path, reason: "Expected an object; null is not supported.")
        }
        if let keys, let unknown = object.keys.sorted().first(where: { !keys.contains($0) }) {
            let prefix = path == "manifest.json" ? "" : "\(path)."
            throw ValidationError(path: "\(prefix)\(unknown)", reason: "Unknown setting.")
        }
        return object
    }

    /// Reads a required string without coercing other JSON types.
    /// - Parameters:
    ///   - value: The supplied value, or nil for a missing field.
    ///   - path: Its manifest location.
    /// - Returns: The supplied string.
    /// - Throws: A validation error for a missing or non-string value.
    private static func string(_ value: Any?, at path: String) throws -> String {
        guard let value = value as? String else {
            throw ValidationError(path: path, reason: "Expected a string.")
        }
        return value
    }

    /// Decodes one atomic color representation.
    /// - Parameters:
    ///   - value: The supplied JSON object.
    ///   - path: The semantic color's manifest location.
    /// - Returns: A symbolic or opaque sRGB color.
    /// - Throws: A validation error for an ambiguous or unsupported representation.
    private static func color(_ value: Any, at path: String) throws -> Color {
        let object = try object(value, at: path, keys: ["system", "srgb"])
        guard object.count == 1 else {
            throw ValidationError(path: path, reason: "Expected exactly one of system or srgb.")
        }
        if let system = object["system"] {
            let name = try string(system, at: "\(path).system")
            guard let color = Color.System(rawValue: name) else {
                throw ValidationError(path: "\(path).system", reason: "Unsupported system color: \(name).")
            }
            return .system(color)
        }
        let hex = try string(object["srgb"], at: "\(path).srgb")
        let digits = hex.dropFirst()
        guard hex.first == "#", hex.utf8.count == 7,
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let number = UInt32(digits, radix: 16) else {
            throw ValidationError(path: "\(path).srgb", reason: "Expected an opaque six-digit #RRGGBB color.")
        }
        return .srgb(red: UInt8((number >> 16) & 255), green: UInt8((number >> 8) & 255), blue: UInt8(number & 255))
    }
}
