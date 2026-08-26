import CoreGraphics
import Foundation

public protocol PhotoLibraryService: Sendable {
    func access() async -> PhotoLibraryAccess
    func requestAccess() async -> PhotoLibraryAccess
    func assets(from offset: Int, limit: Int) async -> [PhotoAsset]
    func resetAssetPaging() async
    func thumbnail(for id: String, maxPixel: CGFloat) async -> CGImage?
    func imageData(for id: String) async -> Data?
}

public extension PhotoLibraryService {
    func latestPhotoThumbnail(maxPixel: CGFloat) async -> CGImage? {
        guard let asset = await assets(from: 0, limit: 1).first else { return nil }
        return await thumbnail(for: asset.id, maxPixel: maxPixel)
    }
}

#if os(iOS)
    import Photos
    import Synchronization

    private final class PendingImageRequest: Sendable {
        private struct State {
            var request: PHImageRequestID?
            var isCancelled = false
        }

        private let state = Mutex(State())

        func adopt(_ request: PHImageRequestID, cancelling manager: PHImageManager) {
            let cancelNow = state.withLock { state -> Bool in
                state.request = request
                return state.isCancelled
            }
            if cancelNow {
                manager.cancelImageRequest(request)
            }
        }

        func cancel(with manager: PHImageManager) {
            let request = state.withLock { state -> PHImageRequestID? in
                state.isCancelled = true
                return state.request
            }
            if let request {
                manager.cancelImageRequest(request)
            }
        }
    }

    public actor PHPhotoLibraryService: PhotoLibraryService {
        private var fetched: PHFetchResult<PHAsset>?

        public init() {}

        public func access() async -> PhotoLibraryAccess {
            Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        }

        public func requestAccess() async -> PhotoLibraryAccess {
            await Self.map(PHPhotoLibrary.requestAuthorization(for: .readWrite))
        }

        public func resetAssetPaging() {
            fetched = nil
        }

        public func assets(from offset: Int, limit: Int) async -> [PhotoAsset] {
            guard await access().canBrowse else { return [] }

            let result = fetched ?? Self.fetchAll()
            fetched = result

            guard offset < result.count else { return [] }
            let upper = min(offset + limit, result.count)
            return (offset ..< upper).map { PhotoAsset(id: result.object(at: $0).localIdentifier) }
        }

        private static func fetchAll() -> PHFetchResult<PHAsset> {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            return PHAsset.fetchAssets(with: .image, options: options)
        }

        public func thumbnail(for id: String, maxPixel: CGFloat) async -> CGImage? {
            guard let asset = Self.asset(id) else { return nil }

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.resizeMode = .fast
            // ponytail: fastFormat calls the handler exactly once. opportunistic
            // calls it twice, and a checked continuation resumed twice traps.
            options.deliveryMode = .fastFormat

            let size = CGSize(width: maxPixel, height: maxPixel)
            let manager = PHImageManager.default()
            let pending = PendingImageRequest()

            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let request = manager.requestImage(
                        for: asset,
                        targetSize: size,
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        continuation.resume(returning: image?.cgImage)
                    }
                    pending.adopt(request, cancelling: manager)
                }
            } onCancel: {
                pending.cancel(with: manager)
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

        public func assets(from _: Int, limit _: Int) async -> [PhotoAsset] {
            []
        }

        public func resetAssetPaging() async {}

        public func thumbnail(for _: String, maxPixel _: CGFloat) async -> CGImage? {
            nil
        }

        public func imageData(for _: String) async -> Data? {
            nil
        }
    }
#endif
