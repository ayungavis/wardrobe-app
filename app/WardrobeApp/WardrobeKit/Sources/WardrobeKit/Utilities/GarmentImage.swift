import Foundation

enum GarmentImage {
    static func data(for item: WardrobeItem, in thumbnails: any GarmentThumbnailRepository) -> Data? {
        item.illustrationFile.flatMap { try? thumbnails.data(forFile: $0) }
            ?? (try? thumbnails.data(forFile: item.cutoutFile))
    }
}
