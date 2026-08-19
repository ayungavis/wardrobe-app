import Foundation

// MARK: - The checkmark (FR-028/029)

// Its own file only because `CaptureFlowViewModel.swift` reached the
// file-length limit, the same way `EditorViewModel+Export` was split off. The
// members below are internal rather than private for that reason alone — this
// extension is still part of the type, just not part of the file.

public extension CaptureFlowViewModel {
    /// The checkmark — the only action that completes the challenge (FR-028).
    /// Guarded twice over: an in-flight flag here, and a same-day check in the
    /// store, so repeated taps can never write two records (FR-029).
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
            // Read back rather than trusted: the editor owns a separate copy of
            // the challenge and saves its edits to the repository, so this
            // value copy has been stale ever since the editor opened. Taking
            // the local one here silently dropped every text and sticker at ✓.
            document: activeRepository.load()?.document ?? challenge.document,
            completedAt: now
        )

        // Wardrobe first, completion last. The two live in different stores, so
        // one transaction is impossible; if the bookkeeping fails the challenge
        // still completes rather than being held hostage by it.
        review.commit(completionID: completion.id, at: now)
        // Photos added and then deleted have nothing left in the document to
        // name them, so this is the last chance to clean them up.
        photoRepository.deleteUnusedOriginals(
            of: completion.document, imported: challenge.importedPhotoIDs
        )

        // History shows the composition, not the capture, so it is rendered
        // once here rather than on every card that scrolls past.
        completion.previewFile = await renderPreview(of: completion)

        completedRepository.append(completion)
        activeRepository.clear() // the photo file stays — History still reads it
        isCompleted = true
        let cardID = challenge.card.id.uuidString
        Log.ui.info("Challenge completed: \(cardID, privacy: .public)")
    }

    /// Best-effort, and deliberately so: a failed render must never cost the
    /// user their completion (FR-028), for the same reason the wardrobe
    /// bookkeeping above cannot hold it hostage. History falls back to
    /// rendering on demand when this returns nil.
    ///
    /// The bytes are the export itself — the very file Save and Share produce —
    /// so what History shows can never drift from what was shared.
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
