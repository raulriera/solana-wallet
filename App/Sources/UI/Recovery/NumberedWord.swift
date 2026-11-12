/// A recovery word and its one-based position in the phrase.
nonisolated struct NumberedWord: Identifiable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    let position: Int
    let text: String

    var id: Int { position }

    var description: String { "NumberedWord" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }
}
