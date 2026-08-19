import Foundation

public protocol PhotoLibrarySaveService: Sendable {
    func save(_ data: Data) async throws
}

#if os(iOS)
    import Photos

    public struct PHPhotoLibrarySaveService: PhotoLibrarySaveService {
        public init() {}

        public func save(_ data: Data) async throws {
            guard await isAuthorized else { throw AppError.photoAccessDenied }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
            } catch {
                throw AppError.photoSaveFailed
            }
        }

        private var isAuthorized: Bool {
            get async {
                let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                guard current == .notDetermined else { return current == .authorized }

                return await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            }
        }
    }
#else
    public struct NoopPhotoLibrarySaveService: PhotoLibrarySaveService {
        public init() {}
        public func save(_: Data) async throws {}
    }
#endif
