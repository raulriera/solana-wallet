/// A wallet workflow with typed preparation and signing operations.
///
/// Signing remains independent of submission; instruction meaning requires separate interpretation.
nonisolated protocol TransactionCoordinating: TransactionPreparing, TransactionSigning {}
