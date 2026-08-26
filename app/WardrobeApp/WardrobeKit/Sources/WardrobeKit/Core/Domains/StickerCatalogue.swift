import Foundation
import SwiftUI

public enum StickerDesign: Equatable, Sendable {
    case emoji(String)
    case symbol(name: String, accent: StickerAccent)
    case image(String)
}

public enum StickerAccent: String, CaseIterable, Sendable {
    case pink, red, orange, yellow, green, blue, purple

    public var gradientColors: [Color] {
        switch self {
        case .pink: [Color(red: 1, green: 0.22, blue: 0.55), Color(red: 0.78, green: 0.12, blue: 0.48)]
        case .red: [Color(red: 1, green: 0.31, blue: 0.25), Color(red: 0.84, green: 0.08, blue: 0.13)]
        case .orange: [Color(red: 1, green: 0.62, blue: 0.08), Color(red: 1, green: 0.31, blue: 0.06)]
        case .yellow: [Color(red: 1, green: 0.91, blue: 0.16), Color(red: 1, green: 0.64, blue: 0.04)]
        case .green: [Color(red: 0.31, green: 0.88, blue: 0.42), Color(red: 0.05, green: 0.58, blue: 0.38)]
        case .blue: [Color(red: 0.20, green: 0.72, blue: 1), Color(red: 0.16, green: 0.30, blue: 0.92)]
        case .purple: [Color(red: 0.72, green: 0.35, blue: 1), Color(red: 0.39, green: 0.15, blue: 0.82)]
        }
    }
}

public struct StickerCatalogueEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let design: StickerDesign
    var displayName: String?
    var keywords: [String] = []
    var category: StickerCategory?
    var index = 0

    public var name: String {
        if let displayName {
            return displayName
        }
        if let category, index > 0 {
            return "\(category.name) \(index)"
        }
        return LocalizedKey.resolve(Self.nameKey(for: id))
    }

    var usesLocalisedName: Bool {
        displayName == nil && category == nil
    }

    func matches(_ query: String) -> Bool {
        if name.localizedStandardContains(query) {
            return true
        }
        if let category, category.name.localizedStandardContains(query) {
            return true
        }
        return keywords.contains { $0.localizedStandardContains(query) }
    }

    static func nameKey(for id: String) -> String {
        "editor.sticker.\(id)"
    }
}

public enum StickerCatalogue {
    public static let emojis: [StickerCatalogueEntry] = [
        StickerCatalogueEntry(id: "emoji.love-face", design: .emoji("🥰")),
        StickerCatalogueEntry(id: "emoji.laugh", design: .emoji("😂")),
        StickerCatalogueEntry(id: "emoji.cool", design: .emoji("😎")),
        StickerCatalogueEntry(id: "emoji.party", design: .emoji("🥳")),
        StickerCatalogueEntry(id: "emoji.star-eyes", design: .emoji("🤩")),
        StickerCatalogueEntry(id: "emoji.heart-eyes", design: .emoji("😍")),
        StickerCatalogueEntry(id: "emoji.heart-hands", design: .emoji("🫶")),
        StickerCatalogueEntry(id: "emoji.fire", design: .emoji("🔥")),
        StickerCatalogueEntry(id: "emoji.sparkles", design: .emoji("✨")),
        StickerCatalogueEntry(id: "emoji.heart", design: .emoji("💖")),
        StickerCatalogueEntry(id: "emoji.red-heart", design: .emoji("❤️")),
        StickerCatalogueEntry(id: "emoji.dizzy", design: .emoji("💫")),
        StickerCatalogueEntry(id: "emoji.raising-hands", design: .emoji("🙌")),
        StickerCatalogueEntry(id: "emoji.ok-hand", design: .emoji("👌")),
        StickerCatalogueEntry(id: "emoji.victory", design: .emoji("✌️")),
        StickerCatalogueEntry(id: "emoji.confetti", design: .emoji("🎉")),
        StickerCatalogueEntry(id: "emoji.hundred", design: .emoji("💯")),
        StickerCatalogueEntry(id: "emoji.check", design: .emoji("✅")),
        StickerCatalogueEntry(id: "emoji.dress", design: .emoji("👗")),
        StickerCatalogueEntry(id: "emoji.jeans", design: .emoji("👖")),
        StickerCatalogueEntry(id: "emoji.sneaker", design: .emoji("👟")),
        StickerCatalogueEntry(id: "emoji.cap", design: .emoji("🧢")),
        StickerCatalogueEntry(id: "emoji.sunglasses", design: .emoji("🕶️")),
        StickerCatalogueEntry(id: "emoji.handbag", design: .emoji("👜")),
        StickerCatalogueEntry(id: "emoji.coat", design: .emoji("🧥")),
        StickerCatalogueEntry(id: "emoji.hat", design: .emoji("👒")),
        StickerCatalogueEntry(id: "emoji.dancer", design: .emoji("💃")),
        StickerCatalogueEntry(id: "emoji.dancing-man", design: .emoji("🕺")),
        StickerCatalogueEntry(id: "emoji.nails", design: .emoji("💅")),
        StickerCatalogueEntry(id: "emoji.flower", design: .emoji("🌸")),
        StickerCatalogueEntry(id: "emoji.rainbow", design: .emoji("🌈")),
        StickerCatalogueEntry(id: "emoji.sun", design: .emoji("☀️")),
        StickerCatalogueEntry(id: "emoji.moon", design: .emoji("🌙")),
        StickerCatalogueEntry(id: "emoji.star", design: .emoji("⭐️")),
        StickerCatalogueEntry(id: "emoji.leaf-fall", design: .emoji("🍂")),
        StickerCatalogueEntry(id: "emoji.snowflake", design: .emoji("❄️")),
        StickerCatalogueEntry(id: "emoji.palm", design: .emoji("🌴")),
        StickerCatalogueEntry(id: "emoji.cherries", design: .emoji("🍒")),
        StickerCatalogueEntry(id: "emoji.strawberry", design: .emoji("🍓")),
        StickerCatalogueEntry(id: "emoji.coffee", design: .emoji("☕️")),
        StickerCatalogueEntry(id: "emoji.bear", design: .emoji("🐻")),
        StickerCatalogueEntry(id: "emoji.butterfly", design: .emoji("🦋")),
        StickerCatalogueEntry(id: "emoji.dog", design: .emoji("🐶")),
        StickerCatalogueEntry(id: "emoji.cat", design: .emoji("🐱")),
        StickerCatalogueEntry(id: "emoji.headphones", design: .emoji("🎧")),
        StickerCatalogueEntry(id: "emoji.camera", design: .emoji("📸")),
        StickerCatalogueEntry(id: "emoji.airplane", design: .emoji("✈️")),
    ]

    public static let offlineStickers: [StickerCatalogueEntry] = [
        StickerCatalogueEntry(id: "sticker.heart", design: .symbol(name: "heart.fill", accent: .pink)),
        StickerCatalogueEntry(id: "sticker.star", design: .symbol(name: "star.fill", accent: .yellow)),
        StickerCatalogueEntry(id: "sticker.sparkles", design: .symbol(name: "sparkles", accent: .purple)),
        StickerCatalogueEntry(id: "sticker.sun", design: .symbol(name: "sun.max.fill", accent: .orange)),
        StickerCatalogueEntry(id: "sticker.cloud", design: .symbol(name: "cloud.fill", accent: .blue)),
        StickerCatalogueEntry(id: "sticker.moon", design: .symbol(name: "moon.fill", accent: .purple)),
        StickerCatalogueEntry(id: "sticker.camera", design: .symbol(name: "camera.fill", accent: .pink)),
        StickerCatalogueEntry(id: "sticker.music", design: .symbol(name: "music.note", accent: .blue)),
        StickerCatalogueEntry(id: "sticker.location", design: .symbol(name: "mappin", accent: .red)),
        StickerCatalogueEntry(id: "sticker.verified", design: .symbol(name: "checkmark.seal.fill", accent: .blue)),
        StickerCatalogueEntry(id: "sticker.flame", design: .symbol(name: "flame.fill", accent: .red)),
        StickerCatalogueEntry(id: "sticker.leaf", design: .symbol(name: "leaf.fill", accent: .green)),
    ]

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

    public static let imageStickers: [StickerCatalogueEntry] = letters + favourites + numbered

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

    public static let all: [StickerCatalogueEntry] = emojis + offlineStickers + imageStickers

    public static func search(_ query: String) -> [StickerCatalogueEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return all.filter { $0.matches(query) }
    }

    public static func entry(id: String) -> StickerCatalogueEntry? {
        all.first { $0.id == id }
    }

    public static func entry(matching emoji: String) -> StickerCatalogueEntry? {
        all.first { $0.design == .emoji(emoji) }
    }

    public static func entries(in category: StickerCategory, recentIDs: [String]) -> [StickerCatalogueEntry] {
        switch category {
        case .recent: recentIDs.compactMap { entry(id: $0) }
        case .wardrobe: []
        case .emoji: emojis
        case .stickers: offlineStickers
        default: imageStickers.filter { $0.category == category }
        }
    }
}

public enum StickerCategory: String, CaseIterable, Identifiable, Sendable {
    case recent, wardrobe, favorite, letter, flower, doodle, drawing, clip, pin, bandage, other,
         emoji, stickers

    public var id: String {
        rawValue
    }

    public var symbolName: String {
        switch self {
        case .recent: "clock"
        case .wardrobe: "tshirt"
        case .favorite: "heart.fill"
        case .letter: "textformat"
        case .flower: "leaf.fill"
        case .doodle: "scribble"
        case .drawing: "pencil.and.outline"
        case .clip: "paperclip"
        case .pin: "pin.fill"
        case .bandage: "bandage.fill"
        case .other: "square.grid.2x2"
        case .emoji: "face.smiling"
        case .stickers: "sparkles"
        }
    }

    var keywords: [String] {
        switch self {
        case .letter: ["letter", "alphabet", "huruf", "abjad"]
        case .flower: ["flower", "bunga", "floral"]
        case .doodle: ["doodle", "coretan", "sketch"]
        case .drawing: ["drawing", "gambar", "sketch"]
        case .clip: ["clip", "klip", "paperclip"]
        case .pin: ["pin", "peniti", "pushpin"]
        case .bandage: ["bandage", "plester", "bandaid"]
        case .favorite: ["favorite", "favorit"]
        case .other: ["other", "lainnya", "misc"]
        case .recent, .wardrobe, .emoji, .stickers: []
        }
    }

    public var name: String {
        LocalizedKey.resolve("editor.sticker.category.\(rawValue)")
    }
}
