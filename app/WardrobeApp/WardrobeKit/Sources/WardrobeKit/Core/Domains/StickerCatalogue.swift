import Foundation
import SwiftUI

public enum StickerDesign: Equatable, Sendable {
    case emoji(String)
    case symbol(name: String, accent: StickerAccent)
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

    public var name: String {
        LocalizedKey.resolve(Self.nameKey(for: id))
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

    public static let all: [StickerCatalogueEntry] = emojis + offlineStickers

    public static func entry(id: String) -> StickerCatalogueEntry? {
        all.first { $0.id == id }
    }

    public static func entry(matching emoji: String) -> StickerCatalogueEntry? {
        all.first { $0.design == .emoji(emoji) }
    }

    public static func entries(in category: StickerCategory, recentIDs: [String]) -> [StickerCatalogueEntry] {
        switch category {
        case .recent: recentIDs.compactMap { entry(id: $0) }
        case .emoji: emojis
        case .stickers: offlineStickers
        }
    }
}

public enum StickerCategory: String, CaseIterable, Identifiable, Sendable {
    case recent, emoji, stickers

    public var id: String {
        rawValue
    }

    public var symbolName: String {
        switch self {
        case .recent: "clock"
        case .emoji: "face.smiling"
        case .stickers: "sparkles"
        }
    }

    public var name: String {
        LocalizedKey.resolve("editor.sticker.category.\(rawValue)")
    }
}
