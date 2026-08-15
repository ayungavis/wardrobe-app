import Foundation

/// A wardrobe item the matcher considers close to the one being viewed, paired
/// with why it thinks so.
///
/// The match comes from `ItemMatching.candidates` unchanged, so this screen and
/// the review drawer agree on what "similar" means — and calibrating the
/// thresholds improves both at once.
struct SimilarItem: Identifiable, Equatable {
    var id: UUID {
        item.id
    }

    let item: WardrobeItem
    let match: ItemMatch
}
