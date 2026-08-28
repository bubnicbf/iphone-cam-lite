/// A tri-state radio reading. `unknown` is not a synonym for `off`: it
/// means the underlying read failed or returned a value this code does
/// not recognize, and must never be treated as proof the radio is either
/// on or off.
public enum RadioState: Sendable, Equatable {
    case on
    case off
    case unknown
}
