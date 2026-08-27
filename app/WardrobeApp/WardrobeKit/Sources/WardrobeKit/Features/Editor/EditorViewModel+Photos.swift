import CoreGraphics
import Foundation

// MARK: - The document's photos (FR-093)

public extension EditorViewModel {
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
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try photoIDs.reduce(into: [UUID: (Data, CGImage?)]()) { result, id in
                        let data = try repository.loadOriginal(id: id)
                        result[id] = (data, ImageDecoding.downsampledImage(from: data, maxPixel: 1600))
                    }
                }.value
                try Task.checkCancellation()

                previewImages = loaded.compactMapValues(\.1)
                originals = .loaded(loaded.mapValues(\.0))
                updateCroppedPreviews()
            } catch is CancellationError {
            } catch {
                Log.report(error)
                originals = .failed(AppError(wrapping: error))
            }
        }
    }

    func addPhoto(_ data: Data, style: PhotoStyle = .polaroid, above layerID: UUID? = nil) {
        do {
            let photoID = try photoRepository.saveOriginal(data)
            challenge.importedPhotoIDs.append(photoID)

            if case var .loaded(originals) = originals {
                originals[photoID] = data
                self.originals = .loaded(originals)
            }
            previewImages[photoID] = ImageDecoding.downsampledImage(from: data, maxPixel: 1600)

            document.insertPhoto(photoID, style: style, above: layerID)
            selectedLayerID = document.photoLayerID(showing: photoID)
            updateCroppedPreviews()
            persistDocument()
        } catch {
            Log.report(error)
            alertError = .photoImportFailed
        }
    }

    var challengePhotoLayerID: UUID? {
        challenge.photoID.flatMap { document.photoLayerID(showing: $0) }
    }

    func canRemove(layerID: UUID) -> Bool {
        layerID != challengePhotoLayerID
    }

    func preview(forPhoto photoID: UUID) -> CGImage? {
        croppedPreviews[photoID] ?? illustration(forItem: photoID)
    }

    func updateCroppedPreviews() {
        var cropped: [UUID: CGImage] = [:]
        for layer in document.layers {
            guard case let .photo(photo) = layer.content,
                  let preview = previewImages[photo.photoID]
            else {
                continue
            }
            cropped[photo.photoID] = Self.cropped(preview, to: photo.crop)
        }
        if case let .photo(id, crop) = document.background, let preview = previewImages[id] {
            cropped[id] = Self.cropped(preview, to: crop)
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
