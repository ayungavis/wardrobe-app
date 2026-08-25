import Foundation

// MARK: - The checkmark (FR-028/029)

public extension CaptureFlowViewModel {
    func completeChallenge(history: [EditorDocument] = []) {
        guard !isCompleting, !isCompleted, challenge.photoID != nil else { return }
        pendingUndoSteps = history
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

        photoRepository.deleteUnusedOriginals(
            of: completion.document, imported: challenge.importedPhotoIDs
        )

        completion.previewFile = await renderPreview(of: completion)

        do {
            let committed = try review.stageCommit(completionID: completion.id, at: now)
            completion.syncQueuedAt = now
            completedRepository.stage(completion)
            let plan = try CompletionSyncPlanner.plan(
                for: completion, items: committed, at: now, history: pendingUndoSteps
            )
            try outbox.stage(
                SyncMutation.completeChallenge(plan.args).queued(id: completion.id),
                at: now
            )
            for upload in plan.uploads {
                uploads.stage(upload)
            }
            try review.commitStaged()
        } catch {
            review.discardStaged()
            Log.report(error, context: Log.Context(operation: "completeChallenge"), logger: Log.ui)
            return
        }

        activeRepository.clear()
        isCompleted = true
        let cardID = challenge.card.id.uuidString
        Log.ui.info("Challenge completed: \(cardID, privacy: .public)")
    }

    // ponytail: stored at full export size, roughly 300 KB a completion.
    // Downscale, or keep a second smaller rendition, when storage complains.
    func renderPreview(of completion: CompletedChallenge) async -> String? {
        var originals: [UUID: Data] = [:]
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
