import CoreFoundation
import Foundation

/// A theme package's manifest.
struct Manifest: Sendable, Equatable {
    let id: UUID
    let name: String
    /// The token values the theme sets, complete or partial.
    let tokens: Tokens.Overrides
    /// The package-relative image paths, keyed by name.
    let assets: [String: String]

    /// Decodes and validates a manifest.
    ///
    /// - Parameter data: The manifest's UTF-8 JSON bytes.
    /// - Returns: The validated manifest.
    /// - Throws: A validation error for the invalid field.
    static func decode(_ data: Data) throws -> Manifest {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ValidationError(path: "manifest.json", reason: "Expected valid JSON.")
        }
        let root = try object(json, at: "manifest.json", keys: ["version", "id", "name", "tokens", "assets"])
        let version = try number(root["version"], at: "version")
        guard version.doubleValue.rounded(.towardZero) == version.doubleValue else {
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
        var overrides = Tokens.Overrides()
        if let suppliedTokens = root["tokens"] {
            let tokens = try object(suppliedTokens, at: "tokens", keys: ["colors", "fontDesign"])
            if let suppliedColors = tokens["colors"] {
                let appearances = try object(suppliedColors, at: "tokens.colors",
                                             keys: Appearance.allCases.map(\.rawValue))
                for appearance in Appearance.allCases {
                    guard let suppliedPalette = appearances[appearance.rawValue] else { continue }
                    let path = "tokens.colors.\(appearance.rawValue)"
                    let palette = try object(suppliedPalette, at: path, keys: Palette.Role.allCases.map(\.rawValue))
                    var values: [Palette.Role: Color] = [:]
                    for role in Palette.Role.allCases {
                        if let value = palette[role.rawValue] {
                            values[role] = try color(value, at: "\(path).\(role.rawValue)")
                        }
                    }
                    overrides.colors[appearance] = values
                }
            }
            if let suppliedDesign = tokens["fontDesign"] {
                overrides.fontDesign = try supported(suppliedDesign, at: "tokens.fontDesign", kind: "font design")
            }
        }
        var assets: [String: String] = [:]
        if let suppliedAssets = root["assets"] {
            let declarations = try object(suppliedAssets, at: "assets")
            for key in declarations.keys.sorted() {
                assets[key] = try string(declarations[key], at: "assets.\(key)")
            }
        }
        return Manifest(id: id, name: name, tokens: overrides, assets: assets)
    }

    /// Encodes the manifest as JSON.
    ///
    /// - Returns: Readable JSON with sorted keys.
    /// - Throws: A JSON serialization error.
    func encode() throws -> Data {
        let palettes = Dictionary(uniqueKeysWithValues: tokens.colors.map { appearance, palette in
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
        var encoded: [String: Any] = ["colors": palettes]
        encoded["fontDesign"] = tokens.fontDesign?.rawValue
        let json: [String: Any] = ["version": 1, "id": id.uuidString, "name": name, "tokens": encoded, "assets": assets]
        var data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    /// Throws if a display name is empty or only whitespace.
    ///
    /// - Parameter name: The display name.
    /// - Throws: A validation error if the name is empty or only whitespace.
    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError(path: "name", reason: "Expected a nonempty display name.")
        }
    }

    /// Reads a JSON object and checks its keys.
    ///
    /// - Parameters:
    ///   - value: A decoded JSON value.
    ///   - path: The value's manifest location.
    ///   - keys: The allowed keys, or `nil` to allow any key.
    /// - Returns: The JSON object.
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

    /// Reads a required JSON string.
    ///
    /// - Parameters:
    ///   - value: The decoded value, or `nil` if the field is missing.
    ///   - path: The value's manifest location.
    /// - Returns: The string.
    /// - Throws: A validation error for a missing or non-string value.
    private static func string(_ value: Any?, at path: String) throws -> String {
        guard let value = value as? String else {
            throw ValidationError(path: path, reason: "Expected a string.")
        }
        return value
    }

    /// Reads a required JSON number.
    ///
    /// - Parameters:
    ///   - value: The decoded value, or `nil` if the field is missing.
    ///   - path: The value's manifest location.
    /// - Returns: The number.
    /// - Throws: A validation error for a missing, Boolean, or non-number value.
    private static func number(_ value: Any?, at path: String) throws -> NSNumber {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw ValidationError(path: path, reason: "Expected a number.")
        }
        return number
    }

    /// Reads a JSON string as one of a type's supported raw values.
    ///
    /// - Parameters:
    ///   - value: The decoded value, or `nil` if the field is missing.
    ///   - path: The value's manifest location.
    ///   - kind: The name of the value's kind for the error message, such as "font design".
    /// - Returns: The value for the string.
    /// - Throws: A validation error for a missing, non-string, or unsupported value.
    private static func supported<Value: RawRepresentable<String>>(_ value: Any?, at path: String, kind: String) throws -> Value {
        let name = try string(value, at: path)
        guard let supported = Value(rawValue: name) else {
            throw ValidationError(path: path, reason: "Unsupported \(kind): \(name).")
        }
        return supported
    }

    /// Decodes a color.
    ///
    /// - Parameters:
    ///   - value: The decoded JSON value.
    ///   - path: The color's manifest location.
    /// - Returns: A system or opaque sRGB color.
    /// - Throws: A validation error for an invalid color.
    private static func color(_ value: Any, at path: String) throws -> Color {
        let object = try object(value, at: path, keys: ["system", "srgb"])
        guard object.count == 1 else {
            throw ValidationError(path: path, reason: "Expected exactly one of system or srgb.")
        }
        if let system = object["system"] {
            return .system(try supported(system, at: "\(path).system", kind: "system color"))
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
