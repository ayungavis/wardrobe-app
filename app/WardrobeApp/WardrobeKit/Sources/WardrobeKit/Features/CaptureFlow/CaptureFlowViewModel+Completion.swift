import Foundation

// MARK: - The checkmark (FR-028/029)

public extension CaptureFlowViewModel {
    func completeChallenge() {
        guard !isCompleting, !isCompleted, challenge.photoID != nil else { return }
        isCompleting = true

        completionTask = Task {
            defer { isCompleting = false }
            await review.finishScanning()
            await commit()
        }
    }

    func commit() async {
        guard let photoID = challenge.photoID else { return }
        let now = Date()
        var completion = CompletedChallenge(
            card: challenge.card,
            photoID: photoID,
            document: activeRepository.load()?.document ?? challenge.document,
            completedAt: now
        )

        review.commit(completionID: completion.id, at: now)
        photoRepository.deleteUnusedOriginals(
            of: completion.document, imported: challenge.importedPhotoIDs
        )

        completion.previewFile = await renderPreview(of: completion)

        completedRepository.append(completion)
        activeRepository.clear() // the photo file stays — History still reads it
        isCompleted = true
        let cardID = challenge.card.id.uuidString
        Log.ui.info("Challenge completed: \(cardID, privacy: .public)")
    }

    /// Best-effort: a failed render must never cost the user their completion
    /// (FR-028). History falls back to rendering on demand when this returns nil.
    ///
    /// ponytail: stored at full export size, roughly 300 KB a completion.
    /// Downscale, or keep a second smaller rendition, when storage complains.
    func renderPreview(of completion: CompletedChallenge) async -> String? {
        var originals: [String: Data] = [:]
        for id in Set(completion.document.photoIDs) {
            originals[id] = try? photoRepository.loadOriginal(id: id)
        }

        do {
            let data = try await ExportService.render(originals: originals, document: completion.document)
            return try previews.save(data, id: completion.id)
        } catch {
            Log.report(error)
            return nil
        }
    }
}
