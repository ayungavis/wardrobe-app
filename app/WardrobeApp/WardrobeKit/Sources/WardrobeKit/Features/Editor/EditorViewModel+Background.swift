import Foundation

// MARK: - Canvas background

public extension EditorViewModel {
    func setBackground(_ background: CanvasBackground) {
        guard document.background != background else { return }
        document.background = background
        persistDocument()
    }

    func setBackgroundPhoto(_ data: Data) {
        do {
            let photoID = try photoRepository.saveOriginal(data)
            challenge.importedPhotoIDs.append(photoID)

            if case var .loaded(originals) = originals {
                originals[photoID] = data
                self.originals = .loaded(originals)
            }
            previewImages[photoID] = ImageDecoding.downsampledImage(from: data, maxPixel: 1600)

            document.background = .photo(id: photoID, crop: nil)
            updateCroppedPreviews()
            persistDocument()
        } catch {
            Log.report(error)
            alertError = .photoImportFailed
        }
    }
}
