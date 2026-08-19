import CoreGraphics
import Foundation

public protocol PhotoLibraryService: Sendable {
    func access() async -> PhotoLibraryAccess
    func requestAccess() async -> PhotoLibraryAccess
    func recentAssets(limit: Int) async -> [PhotoAsset]
    func thumbnail(for id: String, maxPixel: CGFloat) async -> CGImage?
    func imageData(for id: String) async -> Data?
}

public extension PhotoLibraryService {
    func latestPhotoThumbnail(maxPixel: CGFloat) async -> CGImage? {
        guard let asset = await recentAssets(limit: 1).first else { return nil }
        return await thumbnail(for: asset.id, maxPixel: maxPixel)
    }
}

#if os(iOS)
    import Photos

    public actor PHPhotoLibraryService: PhotoLibraryService {
        public init() {}

        public func access() async -> PhotoLibraryAccess {
            Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        }

        public func requestAccess() async -> PhotoLibraryAccess {
            await Self.map(PHPhotoLibrary.requestAuthorization(for: .readWrite))
        }

        public func recentAssets(limit: Int) async -> [PhotoAsset] {
            guard await access().canBrowse else { return [] }

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = limit

            var assets: [PhotoAsset] = []
            PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
                assets.append(PhotoAsset(id: asset.localIdentifier))
            }
            return assets
        }

        public func thumbnail(for id: String, maxPixel: CGFloat) async -> CGImage? {
            guard let asset = Self.asset(id) else { return nil }

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.resizeMode = .fast
            options.deliveryMode = .highQualityFormat

            let size = CGSize(width: maxPixel, height: maxPixel)
            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: size,
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image?.cgImage)
                }
            }
        }

        public func imageData(for id: String) async -> Data? {
            guard let asset = Self.asset(id) else { return nil }

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, _ in
                    continuation.resume(returning: data)
                }
            }
        }

        private static func asset(_ id: String) -> PHAsset? {
            PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        }

        private static func map(_ status: PHAuthorizationStatus) -> PhotoLibraryAccess {
            switch status {
            case .authorized: .authorized
            case .limited: .limited
            case .notDetermined: .notDetermined
            default: .denied
            }
        }
    }
#else
    public struct NoopPhotoLibraryService: PhotoLibraryService {
        public init() {}
        public func access() async -> PhotoLibraryAccess {
            .denied
        }

        public func requestAccess() async -> PhotoLibraryAccess {
            .denied
        }

        public func recentAssets(limit _: Int) async -> [PhotoAsset] {
            []
        }

        public func thumbnail(for _: String, maxPixel _: CGFloat) async -> CGImage? {
            nil
        }

        public func imageData(for _: String) async -> Data? {
            nil
        }
    }
#endif
