import SwiftUI

public enum Elevation {
    case card
    case overlay

    var radius: CGFloat {
        switch self {
        case .card: 8
        case .overlay: 16
        }
    }

    var offsetY: CGFloat {
        switch self {
        case .card: 2
        case .overlay: 8
        }
    }
}

public extension View {
    func appShadow(_ elevation: Elevation) -> some View {
        shadow(color: .black.opacity(0.12), radius: elevation.radius, x: 0, y: elevation.offsetY)
    }
}
