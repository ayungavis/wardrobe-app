import Foundation

/// Add-only save to the user's photo library (FR-031).
public protocol PhotoLibrarySaving: Sendable {
    func save(_ data: Data) async throws
}

#if os(iOS)
    import Photos

    public struct PHPhotoLibrarySaver: PhotoLibrarySaving {
        public init() {}

        public func save(_ data: Data) async throws {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
            } catch {
                throw AppError.photoSaveFailed
            }
        }
    }
#else
    /// macOS host builds (unit tests) never save to a photo library.
    public struct NoopPhotoLibrarySaver: PhotoLibrarySaving {
        public init() {}
        public func save(_: Data) async throws {}
    }
#endif
