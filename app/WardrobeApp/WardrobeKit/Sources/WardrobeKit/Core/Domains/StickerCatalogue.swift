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
        StickerCatalogueEntry(id: "emoji.love-face", design: .emoji("🥰"), keywords: ["love", "cinta", "sayang", "muka"]),
        StickerCatalogueEntry(id: "emoji.laugh", design: .emoji("😂"), keywords: ["laugh", "tertawa", "lucu", "ketawa"]),
        StickerCatalogueEntry(id: "emoji.cool", design: .emoji("😎"), keywords: ["cool", "keren", "kacamata"]),
        StickerCatalogueEntry(id: "emoji.party", design: .emoji("🥳"), keywords: ["party", "pesta", "rayakan"]),
        StickerCatalogueEntry(id: "emoji.star-eyes", design: .emoji("🤩"), keywords: ["star", "bintang", "kagum", "wow"]),
        StickerCatalogueEntry(id: "emoji.heart-eyes", design: .emoji("😍"), keywords: ["love", "cinta", "kagum", "mata"]),
        StickerCatalogueEntry(id: "emoji.heart-hands", design: .emoji("🫶"), keywords: ["heart", "hati", "cinta", "tangan"]),
        StickerCatalogueEntry(id: "emoji.fire", design: .emoji("🔥"), keywords: ["fire", "api", "keren", "panas"]),
        StickerCatalogueEntry(id: "emoji.sparkles", design: .emoji("✨"), keywords: ["sparkle", "kilau", "berkilau", "bintang"]),
        StickerCatalogueEntry(id: "emoji.heart", design: .emoji("💖"), keywords: ["heart", "hati", "cinta"]),
        StickerCatalogueEntry(id: "emoji.red-heart", design: .emoji("❤️"), keywords: ["heart", "hati", "cinta", "merah"]),
        StickerCatalogueEntry(id: "emoji.dizzy", design: .emoji("💫"), keywords: ["dizzy", "pusing", "bintang", "kilau"]),
        StickerCatalogueEntry(id: "emoji.raising-hands", design: .emoji("🙌"), keywords: ["hands", "tangan", "hore", "rayakan"]),
        StickerCatalogueEntry(id: "emoji.ok-hand", design: .emoji("👌"), keywords: ["ok", "oke", "tangan", "setuju"]),
        StickerCatalogueEntry(id: "emoji.victory", design: .emoji("✌️"), keywords: ["peace", "damai", "tangan", "victory"]),
        StickerCatalogueEntry(id: "emoji.confetti", design: .emoji("🎉"), keywords: ["confetti", "pesta", "rayakan", "konfeti"]),
        StickerCatalogueEntry(id: "emoji.hundred", design: .emoji("💯"), keywords: ["hundred", "seratus", "keren"]),
        StickerCatalogueEntry(id: "emoji.check", design: .emoji("✅"), keywords: ["check", "centang", "selesai", "benar"]),
        StickerCatalogueEntry(id: "emoji.dress", design: .emoji("👗"), keywords: ["dress", "gaun", "baju"]),
        StickerCatalogueEntry(id: "emoji.jeans", design: .emoji("👖"), keywords: ["jeans", "celana", "denim"]),
        StickerCatalogueEntry(id: "emoji.sneaker", design: .emoji("👟"), keywords: ["sneaker", "sepatu", "sepatu-kets"]),
        StickerCatalogueEntry(id: "emoji.cap", design: .emoji("🧢"), keywords: ["cap", "topi"]),
        StickerCatalogueEntry(id: "emoji.sunglasses", design: .emoji("🕶️"), keywords: ["sunglasses", "kacamata", "hitam"]),
        StickerCatalogueEntry(id: "emoji.handbag", design: .emoji("👜"), keywords: ["bag", "tas", "handbag"]),
        StickerCatalogueEntry(id: "emoji.coat", design: .emoji("🧥"), keywords: ["coat", "jaket", "mantel"]),
        StickerCatalogueEntry(id: "emoji.hat", design: .emoji("👒"), keywords: ["hat", "topi"]),
        StickerCatalogueEntry(id: "emoji.dancer", design: .emoji("💃"), keywords: ["dance", "menari", "dansa"]),
        StickerCatalogueEntry(id: "emoji.dancing-man", design: .emoji("🕺"), keywords: ["dance", "menari", "dansa"]),
        StickerCatalogueEntry(id: "emoji.nails", design: .emoji("💅"), keywords: ["nails", "kuku", "manikur"]),
        StickerCatalogueEntry(id: "emoji.flower", design: .emoji("🌸"), keywords: ["flower", "bunga", "sakura"]),
        StickerCatalogueEntry(id: "emoji.rainbow", design: .emoji("🌈"), keywords: ["rainbow", "pelangi"]),
        StickerCatalogueEntry(id: "emoji.sun", design: .emoji("☀️"), keywords: ["sun", "matahari", "cerah"]),
        StickerCatalogueEntry(id: "emoji.moon", design: .emoji("🌙"), keywords: ["moon", "bulan", "malam"]),
        StickerCatalogueEntry(id: "emoji.star", design: .emoji("⭐️"), keywords: ["star", "bintang"]),
        StickerCatalogueEntry(id: "emoji.leaf-fall", design: .emoji("🍂"), keywords: ["leaf", "daun", "gugur", "musim"]),
        StickerCatalogueEntry(id: "emoji.snowflake", design: .emoji("❄️"), keywords: ["snow", "salju", "dingin"]),
        StickerCatalogueEntry(id: "emoji.palm", design: .emoji("🌴"), keywords: ["palm", "pohon", "kelapa", "pantai"]),
        StickerCatalogueEntry(id: "emoji.cherries", design: .emoji("🍒"), keywords: ["cherry", "ceri", "buah"]),
        StickerCatalogueEntry(id: "emoji.strawberry", design: .emoji("🍓"), keywords: ["strawberry", "stroberi", "buah"]),
        StickerCatalogueEntry(id: "emoji.coffee", design: .emoji("☕️"), keywords: ["coffee", "kopi", "minum"]),
        StickerCatalogueEntry(id: "emoji.bear", design: .emoji("🐻"), keywords: ["bear", "beruang", "hewan"]),
        StickerCatalogueEntry(id: "emoji.butterfly", design: .emoji("🦋"), keywords: ["butterfly", "kupu-kupu"]),
        StickerCatalogueEntry(id: "emoji.dog", design: .emoji("🐶"), keywords: ["dog", "anjing", "hewan"]),
        StickerCatalogueEntry(id: "emoji.cat", design: .emoji("🐱"), keywords: ["cat", "kucing", "hewan"]),
        StickerCatalogueEntry(id: "emoji.headphones", design: .emoji("🎧"), keywords: ["headphone", "musik", "dengar"]),
        StickerCatalogueEntry(id: "emoji.camera", design: .emoji("📸"), keywords: ["camera", "kamera", "foto"]),
        StickerCatalogueEntry(id: "emoji.airplane", design: .emoji("✈️"), keywords: ["airplane", "pesawat", "terbang"]),
    ]

    public static let offlineStickers: [StickerCatalogueEntry] = [
        StickerCatalogueEntry(
            id: "sticker.heart",
            design: .symbol(name: "heart.fill", accent: .pink),
            keywords: ["heart", "hati", "cinta"]
        ),
        StickerCatalogueEntry(
            id: "sticker.star",
            design: .symbol(name: "star.fill", accent: .yellow),
            keywords: ["star", "bintang"]
        ),
        StickerCatalogueEntry(
            id: "sticker.sparkles",
            design: .symbol(name: "sparkles", accent: .purple),
            keywords: ["sparkle", "kilau", "berkilau"]
        ),
        StickerCatalogueEntry(
            id: "sticker.sun",
            design: .symbol(name: "sun.max.fill", accent: .orange),
            keywords: ["sun", "matahari", "cerah"]
        ),
        StickerCatalogueEntry(
            id: "sticker.cloud",
            design: .symbol(name: "cloud.fill", accent: .blue),
            keywords: ["cloud", "awan", "mendung"]
        ),
        StickerCatalogueEntry(
            id: "sticker.moon",
            design: .symbol(name: "moon.fill", accent: .purple),
            keywords: ["moon", "bulan", "malam"]
        ),
        StickerCatalogueEntry(
            id: "sticker.camera",
            design: .symbol(name: "camera.fill", accent: .pink),
            keywords: ["camera", "kamera", "foto"]
        ),
        StickerCatalogueEntry(
            id: "sticker.music",
            design: .symbol(name: "music.note", accent: .blue),
            keywords: ["music", "musik", "nada"]
        ),
        StickerCatalogueEntry(
            id: "sticker.location",
            design: .symbol(name: "mappin", accent: .red),
            keywords: ["location", "lokasi", "pin", "peta"]
        ),
        StickerCatalogueEntry(
            id: "sticker.verified",
            design: .symbol(name: "checkmark.seal.fill", accent: .blue),
            keywords: ["verified", "centang", "terverifikasi"]
        ),
        StickerCatalogueEntry(
            id: "sticker.flame",
            design: .symbol(name: "flame.fill", accent: .red),
            keywords: ["fire", "api", "panas"]
        ),
        StickerCatalogueEntry(
            id: "sticker.leaf",
            design: .symbol(name: "leaf.fill", accent: .green),
            keywords: ["leaf", "daun", "hijau"]
        ),
    ]

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
        case .wardrobe: ["wardrobe", "lemari", "baju", "garment", "pakaian"]
        case .recent, .emoji, .stickers: []
        }
    }

    public var name: String {
        LocalizedKey.resolve("editor.sticker.category.\(rawValue)")
    }
}
