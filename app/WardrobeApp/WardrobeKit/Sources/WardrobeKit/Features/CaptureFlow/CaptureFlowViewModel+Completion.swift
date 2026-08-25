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
            let plan = try Self.syncPlan(
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

    struct CompletionSyncPlan {
        let args: CompleteChallengeArgsDTO
        let uploads: [MediaUpload]
    }

    internal static func syncPlan(
        for completion: CompletedChallenge,
        items: [ScannedGarment],
        at date: Date,
        history: [EditorDocument] = []
    ) throws -> CompletionSyncPlan {
        let minted = MintedMedia()
        let historyPayload = UndoHistoryPayload.data(for: history)
        let garments = items.compactMap { Self.item($0) }

        let args = CompleteChallengeArgsDTO(
            completionId: completion.id,
            cardId: completion.card.id,
            localDate: Self.localDate(date),
            timeZone: TimeZone.current.identifier,
            completedAt: completion.completedAt,
            photo: CompletionPhotoDTO(
                id: completion.photoID, mediaObjectId: minted.photo, source: "capture"
            ),
            derivative: CompletionDerivativeDTO(id: UUID(), mediaObjectId: minted.derivative),
            document: CompletionDocumentDTO(
                id: completion.document.id,
                schemaVersion: Int32(EditorDocument.currentSchemaVersion),
                mediaObjectId: minted.document,
                historyMediaObjectId: historyPayload.map { _ in minted.history },
                historyStepCount: historyPayload.map { _ in Int32(history.count) }
            ),
            layerPhotoIds: Array(Set(completion.document.photoIDs)),
            items: garments.map(\.dto)
        )

        let uploads = try Self.uploadRows(
            for: completion, minted: minted, historyPayload: historyPayload,
            garments: garments, at: date
        )
        return CompletionSyncPlan(args: args, uploads: uploads)
    }

    private struct MintedMedia {
        let photo = UUID()
        let derivative = UUID()
        let document = UUID()
        let history = UUID()
    }

    private static func uploadRows(
        for completion: CompletedChallenge,
        minted: MintedMedia,
        historyPayload: Data?,
        garments: [PlannedItem],
        at date: Date
    ) throws -> [MediaUpload] {
        var uploads = [
            MediaUpload(
                id: minted.photo, ownerID: completion.id, kind: .original,
                contentType: "image/jpeg",
                source: .photoOriginal(completion.photoID), createdAt: date
            ),
            MediaUpload(
                id: minted.derivative, ownerID: completion.id, kind: .derivative,
                contentType: "image/jpeg",
                source: .previewFile(completion.previewFile ?? ""), createdAt: date
            ),
        ]
        try uploads.append(MediaUpload(
            id: minted.document, ownerID: completion.id, kind: .document,
            contentType: "application/json",
            source: .inline(JSONEncoder().encode(completion.document)), createdAt: date
        ))
        if let historyPayload {
            uploads.append(MediaUpload(
                id: minted.history, ownerID: completion.id, kind: .history,
                contentType: "application/zlib",
                source: .inline(historyPayload), createdAt: date
            ))
        }
        uploads += garments.compactMap(\.cutout).map { cutout in
            MediaUpload(
                id: cutout.mediaID, ownerID: completion.id, kind: .cutout,
                contentType: "image/png",
                source: .thumbnailFile(cutout.file), createdAt: date
            )
        }
        return uploads
    }

    private struct PlannedItem {
        let dto: CompletionItemDTO
        let cutout: (mediaID: UUID, file: String)?
    }

    // ponytail: a cutout ships only for a .new item. A merge deletes its thumbnail
    // at ✓ (stageCommit), so minting a cutout media id there names bytes that will
    // never exist to upload.
    private static func item(_ garment: ScannedGarment) -> PlannedItem? {
        switch garment.decision {
        case .new:
            let cutoutMediaID = UUID()
            return PlannedItem(
                dto: CompletionItemDTO(
                    id: garment.id,
                    wearId: UUID(),
                    category: garment.category.rawValue,
                    name: garment.name,
                    description: garment.description,
                    cutout: CutoutArgsDTO(
                        id: UUID(), mediaObjectId: cutoutMediaID, sourcePhotoId: nil
                    )
                ),
                cutout: (cutoutMediaID, garment.cutoutFile)
            )
        case let .existing(existing):
            return PlannedItem(
                dto: CompletionItemDTO(
                    id: existing,
                    wearId: UUID(),
                    category: garment.category.rawValue,
                    name: garment.name,
                    description: garment.description
                ),
                cutout: nil
            )
        case .discard:
            return nil
        }
    }

    private static func localDate(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
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
