import Foundation

/// Add-only save to the user's photo library (FR-031).
public protocol PhotoLibrarySaveService: Sendable {
    func save(_ data: Data) async throws
}

#if os(iOS)
    import Photos

    public struct PHPhotoLibrarySaveService: PhotoLibrarySaveService {
        public init() {}

        public func save(_ data: Data) async throws {
            // Asked for rather than inferred from a failure: `performChanges`
            // does raise the system prompt on its own, but then a refusal comes
            // back as the same opaque error as a full disk, and the two need
            // different things from the user (PRD §17).
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

        /// Add-only: the app writes one derivative and never reads the library
        /// (PRD §18.2 — no background scanning).
        private var isAuthorized: Bool {
            get async {
                let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                guard current == .notDetermined else { return current == .authorized }

                return await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            }
        }
    }
#else
    /// macOS host builds (unit tests) never save to a photo library.
    public struct NoopPhotoLibrarySaveService: PhotoLibrarySaveService {
        public init() {}
        public func save(_: Data) async throws {}
    }
#endif
