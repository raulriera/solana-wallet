import Portfolio
import Privacy
import Transactions

/// An asset that private balances hold.
nonisolated enum PrivateAsset: Hashable, Sendable, CaseIterable {
    case sol
    case token(PrivateToken)

    static let allCases: [PrivateAsset] = [.sol] + PrivateToken.allCases.map(PrivateAsset.token)

    /// Creates the asset of a portfolio holding, or `nil` for a token that private balances don't hold.
    ///
    /// - Parameter holding: The holding's identity.
    init?(_ holding: Holding.Identity) {
        switch holding {
        case .nativeSOL: self = .sol
        case .asset(let mint):
            guard let token = PrivateToken(rawValue: mint) else { return nil }
            self = .token(token)
        }
    }

    /// The identity of the asset's portfolio holding.
    var holding: Holding.Identity {
        switch self {
        case .sol: .nativeSOL
        case .token(let token): .asset(token.rawValue)
        }
    }

    /// Creates the asset of a mint, or `nil` for a token that private balances don't hold.
    ///
    /// - Parameter mint: The token's mint, or `nil` for SOL.
    init?(mint: Address?) {
        self.init(mint.map { .asset($0.value) } ?? .nativeSOL)
    }

    /// The number of decimal places in the asset's amounts.
    var decimals: UInt8 {
        switch self {
        case .sol: 9
        case .token(.usdc), .token(.usdt), .token(.devnetUSDC): 6
        }
    }

    /// Returns the public lamports that a move of an amount of the asset pays into or takes out of the pool.
    ///
    /// - Parameter amount: The moved amount, in the asset's smallest unit.
    /// - Returns: The amount for SOL, or zero for a token, which moves no lamports.
    func lamports(moving amount: UInt64) -> UInt64 {
        self == .sol ? amount : 0
    }

    /// Returns the instruction that moves an amount of the asset from a public account into a private balance.
    ///
    /// - Parameters:
    ///   - amount: The amount, in the asset's smallest unit.
    ///   - depositor: The account that pays and signs.
    ///   - recipient: The private balance that receives the asset.
    ///   - treeID: The ID of the tree that receives the note.
    /// - Returns: The deposit instruction.
    /// - Throws: A validation error if the amount or an address is invalid.
    func deposit(_ amount: UInt64, from depositor: Address, to recipient: Recipient, treeID: UInt16) throws
        -> Instruction {
        switch self {
        case .sol: try ShieldedPool.deposit(lamports: amount, from: depositor, to: recipient, treeID: treeID)
        case .token(let token): try ShieldedPool.deposit(amount, of: token, from: depositor, to: recipient, treeID: treeID)
        }
    }

    /// Returns the destination that withdraws the asset to an owner's public balance.
    ///
    /// - Parameter owner: The account whose public balance receives the asset.
    /// - Returns: The withdrawal destination.
    func withdrawal(to owner: Address) -> PrivateSpend.Destination {
        switch self {
        case .sol: .withdrawal(owner)
        case .token(let token): .tokenWithdrawal(token, owner: owner)
        }
    }

    /// Returns the notes with a deposit of the asset pending.
    ///
    /// - Parameters:
    ///   - amount: The deposited amount, in the asset's smallest unit.
    ///   - state: The account's notes.
    ///   - signature: The deposit's signature.
    /// - Returns: The notes with the deposit pending.
    /// - Throws: A validation error if the pending amount overflows.
    func recording(depositOf amount: UInt64, in state: NoteSyncState, signature: String) throws -> NoteSyncState {
        switch self {
        case .sol: try state.recording(depositOf: amount, signature: signature)
        case .token(let token): try state.recording(depositOf: amount, of: token, signature: signature)
        }
    }

    /// Returns the available and pending amounts of the asset in an account's notes.
    ///
    /// - Parameter state: The account's notes.
    /// - Returns: The amounts, in the asset's smallest unit.
    func balance(in state: NoteSyncState) -> PrivateBalanceStatus.Balance {
        switch self {
        case .sol: PrivateBalanceStatus.Balance(available: state.spendableLamports, pending: state.pendingLamports)
        case .token(let token):
            PrivateBalanceStatus.Balance(available: state.spendableAmount(of: token), pending: state.pendingAmount(of: token))
        }
    }
}
