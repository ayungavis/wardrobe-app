import Foundation

@MainActor
public protocol PurgeService: AnyObject {
    func purgeAccountData() throws
}

@MainActor
public final class LocalPurgeService: PurgeService {
    private let wardrobe: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository
    private let completions: CompletedChallengeRepository
    private let previews: CompletionPreviewRepository
    private let photos: PhotoRepository
    private let active: ActiveChallengeRepository
    private let media: MediaRepository
    private let uploads: any MediaUploadRepository
    private let outbox: any OutboxRepository
    private let diagnostics: any DiagnosticsStore
    private let cursor: any CursorStore

    public init(
        wardrobe: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository,
        completions: CompletedChallengeRepository,
        previews: CompletionPreviewRepository,
        photos: PhotoRepository,
        active: ActiveChallengeRepository,
        media: MediaRepository,
        uploads: any MediaUploadRepository,
        outbox: any OutboxRepository,
        diagnostics: any DiagnosticsStore,
        cursor: any CursorStore
    ) {
        self.wardrobe = wardrobe
        self.thumbnails = thumbnails
        self.completions = completions
        self.previews = previews
        self.photos = photos
        self.active = active
        self.media = media
        self.uploads = uploads
        self.outbox = outbox
        self.diagnostics = diagnostics
        self.cursor = cursor
    }

    public func purgeAccountData() throws {
        for completion in completions.load() {
            photos.deleteOriginals(of: completion.document, and: completion.photoID)
        }
        try previews.deleteAll()
        completions.removeAll()
        active.clear()
        try wardrobe.deleteAll()
        try thumbnails.deleteAll()
        try media.clearCache()
        try uploads.removeAll()
        try outbox.removeAll()
        try diagnostics.removeAll()
        try cursor.reset()
    }
}
