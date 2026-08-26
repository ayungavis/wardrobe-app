import Foundation

public struct CardGarment: Equatable, Sendable {
    public let data: Data
    public let name: String

    public init(data: Data, name: String) {
        self.data = data
        self.name = name
    }
}

public struct CardGarments: Equatable, Sendable {
    public let top: CardGarment?
    public let bottom: CardGarment?

    public init(top: CardGarment? = nil, bottom: CardGarment? = nil) {
        self.top = top
        self.bottom = bottom
    }

    public var isEmpty: Bool {
        top == nil && bottom == nil
    }
}
