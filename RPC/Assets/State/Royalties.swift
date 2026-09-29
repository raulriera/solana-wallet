public import Foundation

extension Asset.State {
    /// An asset's reported royalty policy.
    public struct Royalties: Codable, Sendable, Equatable {
        /// The royalty model.
        public let model: String?
        /// The royalty target.
        public let target: String?
        /// The royalty expressed as a fraction.
        public let fraction: Decimal?
        /// The royalty in basis points.
        public let basisPoints: UInt16?
        /// Whether the primary sale has occurred.
        public let hasPrimarySale: Bool?
        /// Whether the royalty policy is locked.
        public let isLocked: Bool?

        /// Creates royalties information without provider-specific field names.
        /// - Parameters:
        ///   - model: The royalty model.
        ///   - target: The royalty target.
        ///   - fraction: The royalty expressed as a fraction.
        ///   - basisPoints: The royalty in basis points.
        ///   - hasPrimarySale: Whether the primary sale has occurred.
        ///   - isLocked: Whether the royalty policy is locked.
        public init(
            model: String? = nil,
            target: String? = nil,
            fraction: Decimal? = nil,
            basisPoints: UInt16? = nil,
            hasPrimarySale: Bool? = nil,
            isLocked: Bool? = nil
        ) {
            self.model = model
            self.target = target
            self.fraction = fraction
            self.basisPoints = basisPoints
            self.hasPrimarySale = hasPrimarySale
            self.isLocked = isLocked
        }
    }
}
