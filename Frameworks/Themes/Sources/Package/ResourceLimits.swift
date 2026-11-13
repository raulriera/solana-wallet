/// The resource limits for untrusted package input.
enum ResourceLimits {
    static let manifestBytes = 1_048_576
    static let assetBytes = 16_777_216
    static let totalAssetBytes = 67_108_864
    static let imagePixels = 16_777_216

    /// Throws if a byte count is negative or exceeds a limit.
    ///
    /// - Parameters:
    ///   - count: The byte count.
    ///   - limit: The file limit or remaining package allowance.
    ///   - path: The input's location in the package.
    /// - Throws: A validation error if the byte count is outside the allowed range.
    static func checkBytes(_ count: Int64, limit: Int, path: String) throws {
        guard count >= 0, count <= limit else {
            throw ValidationError(path: path, kind: .tooLarge)
        }
    }
}
