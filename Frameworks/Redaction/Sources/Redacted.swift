/// A type whose descriptions and mirror show only its type name.
///
/// Adopt `Redacted` in types that hold secrets, such as keys and recovery phrases, so `print`, `dump`, string
/// interpolation, logs, and the debugger never show their stored values.
public protocol Redacted: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension Redacted {
    public var description: String { String(describing: Self.self) }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
