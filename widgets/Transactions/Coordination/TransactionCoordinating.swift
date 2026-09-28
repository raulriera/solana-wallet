/// A wallet workflow with typed preparation, signing, and submission operations.
///
/// Signing remains independent of submission; instruction meaning requires separate interpretation.
nonisolated protocol TransactionCoordinating: TransactionPreparing, TransactionSigning, TransactionSubmitting {}
