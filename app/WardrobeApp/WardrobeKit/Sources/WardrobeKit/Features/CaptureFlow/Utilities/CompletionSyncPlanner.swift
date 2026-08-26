import Foundation

struct CompletionSyncPlan {
    let args: CompleteChallengeArgsDTO
    let uploads: [MediaUpload]
}

enum CompletionSyncPlanner {
    static func plan(
        for completion: CompletedChallenge,
        items: [ScannedGarment],
        at date: Date,
        history: [EditorDocument] = []
    ) throws -> CompletionSyncPlan {
        let minted = MintedMedia()
        let historyPayload = UndoHistoryPayload.data(for: history)
        let garments = items.compactMap { item($0) }
        let canvasPhotos = Array(Set(completion.document.photoIDs))
            .filter { $0 != completion.photoID }
            .map { (id: $0, media: UUID()) }

        let args = CompleteChallengeArgsDTO(
            completionId: completion.id,
            cardId: completion.card.id,
            localDate: localDate(date),
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
            layerPhotos: canvasPhotos.map {
                CompletionPhotoDTO(id: $0.id, mediaObjectId: $0.media, source: "import")
            },
            items: garments.map(\.dto)
        )

        var uploads = try uploadRows(
            for: completion, minted: minted, historyPayload: historyPayload,
            garments: garments, at: date
        )
        uploads += canvasPhotos.map {
            MediaUpload(
                id: $0.media, ownerID: completion.id, kind: .original,
                contentType: "image/jpeg", source: .photoOriginal($0.id), createdAt: date
            )
        }
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
                    wearId: garment.wearID,
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
                    wearId: garment.wearID,
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
        LocalDay.string(from: date)
    }
}
