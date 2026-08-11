import CoreGraphics
import Foundation

/// Supplies the newest library photo for the gallery button's thumbnail.
///
/// Purely cosmetic: picking a photo goes through the system photo picker,
/// which needs no permission at all, so a nil thumbnail is a fine outcome.
/// Implementations must **never** trigger a permission prompt — PRD §18.1
/// only allows asking at the action that needs it, and a decoration is not
/// that action.
public protocol PhotoLibraryPreviewing: Sendable {
    func latestPhotoThumbnail(maxPixel: CGFloat) async -> CGImage?
}

#if os(iOS)
    import Photos

    public struct PHPhotoLibraryPreview: PhotoLibraryPreviewing {
        public init() {}

        public func latestPhotoThumbnail(maxPixel: CGFloat) async -> CGImage? {
            // Read what we already may read; never prompt for a thumbnail.
            // ponytail: users who never grant library access simply get the
            // icon — add an explicit "show my recents" affordance if the
            // thumbnail turns out to matter enough to ask for.
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else { return nil }

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else {
                return nil
            }

            guard let data = await imageData(for: asset) else { return nil }
            let bytes = data
            let budget = maxPixel
            return await Task.detached(priority: .utility) {
                ImageDecoding.downsampledImage(from: bytes, maxPixel: budget)
            }.value
        }

        /// `requestImageDataAndOrientation` calls its handler exactly once —
        /// unlike `requestImage`, which can deliver a degraded image first and
        /// would resume the continuation twice.
        private func imageData(for asset: PHAsset) async -> Data? {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast

            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, _ in
                    continuation.resume(returning: data)
                }
            }
        }
    }
#else
    /// macOS host builds (unit tests) have no photo library to preview.
    public struct NoopPhotoLibraryPreview: PhotoLibraryPreviewing {
        public init() {}
        public func latestPhotoThumbnail(maxPixel _: CGFloat) async -> CGImage? {
            nil
        }
    }
#endif
