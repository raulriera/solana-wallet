/// Reads the ledger epoch used to select a Token-2022 transfer-fee schedule.
public struct GetEpochInfo: RPCRequest {
    /// The provider-neutral JSON-RPC method name.
    public static let method = "getEpochInfo"

    /// An epoch observation with the absolute slot used to evaluate it.
    public struct Response: Decodable, Sendable {
        /// The current epoch number.
        public let epoch: UInt64
        /// The absolute ledger slot corresponding to the observation.
        public let absoluteSlot: UInt64

        /// Creates the values needed to select and contextualize a fee schedule.
        ///
        /// - Parameters:
        ///   - epoch: The current ledger epoch.
        ///   - absoluteSlot: The corresponding absolute slot.
        public init(epoch: UInt64, absoluteSlot: UInt64) {
            self.epoch = epoch
            self.absoluteSlot = absoluteSlot
        }
    }

    private let configuration: LedgerConfiguration

    /// Creates an epoch request at the selected confirmation level.
    ///
    /// - Parameters:
    ///   - commitment: The confirmation level, defaulting to `confirmed`.
    ///   - minContextSlot: The earliest acceptable observation slot, or `nil`.
    public init(commitment: Commitment = .confirmed, minContextSlot: UInt64? = nil) {
        configuration = LedgerConfiguration(commitment: commitment, minContextSlot: minContextSlot)
    }

    /// Encodes the ledger constraints as a single positional configuration.
    ///
    /// - Parameter encoder: The encoder receiving the parameter array.
    /// - Throws: An encoding error if the configuration cannot be represented.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(configuration)
    }
}
