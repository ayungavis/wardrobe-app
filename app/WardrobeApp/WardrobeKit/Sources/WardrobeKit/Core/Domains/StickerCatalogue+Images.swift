import Foundation

public extension StickerCatalogue {
    // MARK: - Image stickers

    private static let letterGlyphs = [
        "Z",
        "Y",
        "X",
        "W",
        "V",
        "U",
        "T",
        "S",
        "Q",
        "R",
        "O",
        "N",
        "P",
        "M",
        "K",
        "L",
        "H",
        "J",
        "I",
        "G",
        "F",
        "E",
        "D",
        "B",
        "C",
        "A",
        "Z",
        "Y",
        "X",
        "W",
        "V",
        "U",
        "T",
        "S",
        "R",
        "Q",
        "P",
        "O",
        "N",
        "M",
        "K",
        "L",
        "H",
        "J",
        "I",
        "G",
        "F",
        "E",
        "B",
        "D",
        "C",
        "A",
    ]

    private static let favouriteNames = ["Balloon animal dog",
                                         "BandAid ouch",
                                         "Binder clip pink",
                                         "Blue Jeans Pocket",
                                         "Boquet flowers",
                                         "Boquet flowers",
                                         "Butterfly",
                                         "Camera black white",
                                         "Clothes pin",
                                         "Clover black white",
                                         "Coquette ribbon",
                                         "Flower Blue",
                                         "Flower Metallic Silver",
                                         "Heart pink",
                                         "Kiss lips",
                                         "Nature flower",
                                         "Paper plane doodle",
                                         "Paperclip pink",
                                         "Paperclip red",
                                         "Party hat silver metallic",
                                         "Pink patch heart",
                                         "Push pin silver metallic",
                                         "Red cherry",
                                         "Red push pin",
                                         "Safety pin",
                                         "Smiley face doodle",
                                         "Sparkle Metallic Silver",
                                         "Sparkling Disco Ball Silver",
                                         "Star Bead Pink",
                                         "Star Bead Yellow",
                                         "Star Metallic Silver",
                                         "Surprised point arrow"]

    private static let favouriteKeywords = ["animal balloon dog",
                                            "bandaid ouch",
                                            "binder clip pink",
                                            "blue jeans pocket",
                                            "boquet flowers",
                                            "boquet flowers",
                                            "butterfly",
                                            "black camera white",
                                            "clothes pin",
                                            "black clover white",
                                            "coquette ribbon",
                                            "blue flower",
                                            "flower metallic silver",
                                            "heart pink",
                                            "kiss lips",
                                            "flower nature",
                                            "doodle paper plane",
                                            "paperclip pink",
                                            "paperclip red",
                                            "hat metallic party silver",
                                            "heart patch pink",
                                            "metallic pin push silver",
                                            "cherry red",
                                            "pin push red",
                                            "pin safety",
                                            "doodle face smiley",
                                            "metallic silver sparkle",
                                            "ball disco silver sparkling",
                                            "bead pink star",
                                            "bead star yellow",
                                            "metallic silver star",
                                            "arrow point surprised"]

    private static let numberedCategories: [(category: StickerCategory, count: Int)] = [
        (.doodle, 35), (.flower, 24), (.clip, 21), (.drawing, 20), (.bandage, 15), (.other, 12), (.pin, 10),
    ]

    static let imageStickers: [StickerCatalogueEntry] = letters + favourites + numbered

    private static var letters: [StickerCatalogueEntry] {
        letterGlyphs.enumerated().map { offset, glyph in
            entry(.letter, offset + 1, name: glyph, keywords: [glyph] + StickerCategory.letter.keywords)
        }
    }

    private static var favourites: [StickerCatalogueEntry] {
        favouriteNames.enumerated().map { offset, name in
            let words = favouriteKeywords[offset].split(separator: " ").map(String.init)
            return entry(.favorite, offset + 1, name: name, keywords: words)
        }
    }

    private static var numbered: [StickerCatalogueEntry] {
        numberedCategories.flatMap { category, count in
            (1 ... count).map { entry(category, $0, name: nil, keywords: category.keywords) }
        }
    }

    private static func entry(
        _ category: StickerCategory,
        _ index: Int,
        name: String?,
        keywords: [String]
    ) -> StickerCatalogueEntry {
        StickerCatalogueEntry(
            id: "sticker.\(category.rawValue).\(index)",
            design: .image("sticker-\(category.rawValue)-\(index)"),
            displayName: name,
            keywords: keywords,
            category: category,
            index: index
        )
    }
}
