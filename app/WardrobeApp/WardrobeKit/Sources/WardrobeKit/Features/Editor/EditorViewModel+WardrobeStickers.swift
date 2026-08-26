import CoreGraphics
import Foundation

// MARK: - Wardrobe items as stickers (FR-019/FR-081)

extension EditorViewModel {
    // MARK: - The catalogue tray

    public var recentStickerIDs: [String] {
        preferencesRepository.load().knownRecentStickerIDs
    }

    public func addSticker(_ entry: StickerCatalogueEntry) {
        document.appendSticker(.catalogue(entry.id))
        selectedLayerID = document.layers.last?.id
        isStickerPickerPresented = false
        persistDocument()
        rememberSticker(entry.id)
    }

    private func rememberSticker(_ id: String) {
        var preferences = preferencesRepository.load()
        preferences.remember(stickerID: id)
        preferencesRepository.save(preferences)
    }

    func loadWardrobeStickers() {
        guard let wardrobeRepository, let thumbnails else { return }
        let items = (try? wardrobeRepository.items()) ?? []
        wardrobeStickers = items.compactMap { item in
            guard let file = item.illustrationFile,
                  let data = try? thumbnails.data(forFile: file),
                  let image = ImageDecoding.downsampledImage(from: data, maxPixel: 512)
            else {
                return nil
            }
            return WardrobeSticker(id: item.id, name: item.name, image: image)
        }
    }

    func illustration(forItem id: UUID) -> CGImage? {
        wardrobeStickers.first { $0.id == id }?.image
    }

    func illustrationBytes(in document: EditorDocument) -> [UUID: Data] {
        guard let thumbnails else { return [:] }
        let items = wardrobeRepository.flatMap { try? $0.items() } ?? []
        var bytes: [UUID: Data] = [:]
        for layer in document.layers {
            guard case let .sticker(content) = layer.content,
                  let itemID = content.art.wardrobeItemID,
                  let file = items.first(where: { $0.id == itemID })?.illustrationFile,
                  let data = try? thumbnails.data(forFile: file)
            else {
                continue
            }
            bytes[itemID] = data
        }
        return bytes
    }

    // ponytail: recents stay catalogue-only. knownRecentStickerIDs filters ids the
    // catalogue does not ship, so an item there would vanish without a word.
    func addItemSticker(_ sticker: WardrobeSticker) {
        document.appendSticker(.item(sticker.id))
        selectedLayerID = document.layers.last?.id
        isStickerPickerPresented = false
        persistDocument()
    }
}
