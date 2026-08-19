import Foundation
import SwiftUI

public enum CanvasBackground: Equatable, Sendable {
    case palette(Palette)
    case photo(id: String, crop: CropSpec?)

    public static let `default` = CanvasBackground.palette(.white)

    public enum Palette: String, CaseIterable, Identifiable, Sendable {
        case white, cream, blush, lavender, sky, mint, sunset, midnight

        public var id: String {
            rawValue
        }

        public var colors: [Color] {
            switch self {
            case .white: [.white, .white]
            case .cream: [Color(red: 1, green: 0.97, blue: 0.88), Color(red: 0.98, green: 0.90, blue: 0.76)]
            case .blush: [Color(red: 1, green: 0.89, blue: 0.92), Color(red: 0.97, green: 0.66, blue: 0.77)]
            case .lavender: [Color(red: 0.91, green: 0.86, blue: 1), Color(red: 0.68, green: 0.55, blue: 0.94)]
            case .sky: [Color(red: 0.78, green: 0.93, blue: 1), Color(red: 0.34, green: 0.68, blue: 0.96)]
            case .mint: [Color(red: 0.82, green: 0.98, blue: 0.88), Color(red: 0.34, green: 0.78, blue: 0.61)]
            case .sunset: [
                    Color(red: 1, green: 0.72, blue: 0.38),
                    Color(red: 0.96, green: 0.34, blue: 0.55),
                    Color(red: 0.43, green: 0.25, blue: 0.76),
                ]
            case .midnight: [Color(red: 0.08, green: 0.10, blue: 0.22), Color(red: 0.25, green: 0.13, blue: 0.42)]
            }
        }

        public var name: String {
            LocalizedKey.resolve(nameKey)
        }

        var nameKey: String {
            "editor.background.\(rawValue)"
        }
    }

    public var photoID: String? {
        guard case let .photo(id, _) = self else { return nil }
        return id
    }

    public var crop: CropSpec? {
        guard case let .photo(_, crop) = self else { return nil }
        return crop
    }

    public var name: String {
        switch self {
        case let .palette(palette): palette.name
        case .photo: LocalizedKey.resolve("editor.background.photo")
        }
    }
}

extension CanvasBackground: Codable {
    enum CodingKeys: String, CodingKey {
        case photoID, crop
    }

    public init(from decoder: Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            self = .palette(Palette(rawValue: raw) ?? .white)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try .photo(
            id: container.decode(String.self, forKey: .photoID),
            crop: container.decodeIfPresent(CropSpec.self, forKey: .crop)
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .palette(palette):
            var container = encoder.singleValueContainer()
            try container.encode(palette.rawValue)
        case let .photo(id, crop):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .photoID)
            try container.encodeIfPresent(crop, forKey: .crop)
        }
    }
}
