import Foundation

struct SimilarItem: Identifiable, Equatable {
    var id: UUID {
        item.id
    }

    let item: WardrobeItem
    let match: ItemMatch
}
