import CoreGraphics
import Foundation

struct WardrobeSticker: Identifiable, Equatable {
    let id: UUID
    let name: String
    let image: CGImage

    static func == (lhs: WardrobeSticker, rhs: WardrobeSticker) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}
