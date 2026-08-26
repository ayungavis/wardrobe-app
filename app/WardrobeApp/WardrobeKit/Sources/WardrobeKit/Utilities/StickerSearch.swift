import Foundation

enum StickerSearch {
    static func garments(_ garments: [WardrobeSticker], matching query: String) -> [WardrobeSticker] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let category = StickerCategory.wardrobe
        let named = category.keywords + [category.name]
        let wholeCategory = named.contains { $0.localizedStandardContains(query) }
        guard !wholeCategory else { return garments }

        return garments.filter { $0.name.localizedStandardContains(query) }
    }
}
