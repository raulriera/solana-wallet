/// An RPC that submits transactions for a tip and a minimum priority fee.
public protocol SubmissionProviding: RPC {
    /// The tip and minimum priority fee that every submission through this provider pays.
    var submissionRequirements: SubmissionRequirements { get }
}
