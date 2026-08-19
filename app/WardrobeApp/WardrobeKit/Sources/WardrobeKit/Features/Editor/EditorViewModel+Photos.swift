import CoreGraphics
import Foundation

// MARK: - The document's photos (FR-093)

/// Its own file only because `EditorViewModel.swift` reached the type-body
/// limit — the maps it fills are declared there, and are internal for the
/// same reason.
public extension EditorViewModel {
    /// Loads every photo the document draws, not just the challenge's own.
    ///
    /// A document can hold more than one photo layer (FR-093), and each carries
    /// its own id and its own crop — so the pixels are a lookup, never a single
    /// image handed to every layer.
    func load() {
        let photoIDs = document.photoIDs
        guard !photoIDs.isEmpty else {
            originals = .failed(.unexpected)
            return
        }

        loadTask?.cancel()
        originals = .loading

        loadTask = Task {
            do {
                let repository = photoRepository
                // Full decode + downsample stay off the main actor.
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try photoIDs.reduce(into: [String: (Data, CGImage?)]()) { result, id in
                        let data = try repository.loadOriginal(id: id)
                        result[id] = (data, ImageDecoding.downsampledImage(from: data, maxPixel: 1600))
                    }
                }.value
                try Task.checkCancellation()

                previewImages = loaded.compactMapValues(\.1)
                originals = .loaded(loaded.mapValues(\.0))
                updateCroppedPreviews()
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                originals = .failed(AppError(wrapping: error))
            }
        }
    }

    /// Adds a picked photo as a new polaroid layer (FR-093).
    ///
    /// The bytes go to the photo repository and the document stores only the
    /// id — never the pixels. Embedding them, as the prototype does, would put
    /// photo bytes inside the payload that syncs after ✓ and would break §18.5's
    /// separation of originals from derivatives.
    ///
    /// It does not touch `challenge.photoID`: the challenge keeps exactly one
    /// photo, and this is decoration.
    func addPhoto(_ data: Data) {
        do {
            let photoID = try photoRepository.saveOriginal(data)
            challenge.importedPhotoIDs.append(photoID)

            // The bytes are already in hand, so the preview goes straight in
            // rather than sending `load()` back to disk for everything.
            if case var .loaded(originals) = originals {
                originals[photoID] = data
                self.originals = .loaded(originals)
            }
            previewImages[photoID] = ImageDecoding.downsampledImage(from: data, maxPixel: 1600)

            document.appendPhoto(photoID)
            selectedLayerID = document.layers.last?.id
            updateCroppedPreviews()
            persistDocument()
        } catch {
            Log.report(error)
            alertError = .photoImportFailed
        }
    }

    /// The layer showing the challenge's own photo, if the document still has
    /// it. Derived from `ActiveChallenge.photoID` rather than flagged in the
    /// document: a document reopened from History will protect a different
    /// photo, and two copies of that fact could disagree.
    var challengePhotoLayerID: UUID? {
        challenge.photoID.flatMap { document.photoLayerID(showing: $0) }
    }

    /// Everything but the challenge's own photo can go. Deleting that one would
    /// leave a challenge that completes legitimately and shares a picture with
    /// no photo in it — `CompletedChallenge` names it, and the export renders
    /// the document.
    func canRemove(layerID: UUID) -> Bool {
        layerID != challengePhotoLayerID
    }

    /// The pixels a photo layer should draw, already cropped.
    func preview(forPhoto photoID: String) -> CGImage? {
        croppedPreviews[photoID]
    }

    /// Recomputes every photo's cropped preview. Called when the photos load
    /// and when a crop is committed — not on the render path.
    func updateCroppedPreviews() {
        var cropped: [String: CGImage] = [:]
        for layer in document.layers {
            guard case let .photo(photo) = layer.content,
                  let preview = previewImages[photo.photoID]
            else {
                continue
            }
            cropped[photo.photoID] = Self.cropped(preview, to: photo.crop)
        }
        croppedPreviews = cropped
    }

    private static func cropped(_ image: CGImage, to crop: CropSpec?) -> CGImage {
        guard let crop else { return image }

        let rect = CGRect(
            x: crop.rect.origin.x * CGFloat(image.width),
            y: crop.rect.origin.y * CGFloat(image.height),
            width: crop.rect.width * CGFloat(image.width),
            height: crop.rect.height * CGFloat(image.height)
        ).integral
        return image.cropping(to: rect) ?? image
    }
}
