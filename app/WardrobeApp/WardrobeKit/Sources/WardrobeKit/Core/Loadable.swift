/// Explicit async-load state — replaces boolean flag combinations.
public enum Loadable<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)
}
