import Foundation

// MARK: - Editor

public extension AppContainer {
    func makeEditorViewModel(
        challenge: ActiveChallenge,
        review: GarmentReviewModel
    ) -> EditorViewModel {
        EditorViewModel(
            challenge: challenge,
            activeRepository: activeChallengeRepository,
            photoRepository: photoRepository,
            librarySaver: Self.defaultLibrarySaver(),
            preferencesRepository: preferencesRepository,
            wardrobeRepository: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository,
            requestTemplate: { [self] request in try await sendTemplateRequest(request) },
            review: review,
            needsUploadConsent: needsUploadConsentPrompt,
            makeConsent: { [self] in makeConsentViewModel() }
        )
    }

    private func sendTemplateRequest(_ request: TemplateRequest) async throws -> UUID {
        let media = makeMediaRepository()
        let personID = UUID.v7()
        try await media.upload(request.photo, id: personID, kind: .original, contentType: "image/jpeg")

        var garments: [TemplateGarmentDTO] = []
        for garment in request.garments {
            let mediaID = UUID.v7()
            try await media.upload(garment.cutout, id: mediaID, kind: .cutout, contentType: "image/png")
            garments.append(TemplateGarmentDTO(
                mediaId: mediaID, name: garment.name, wears: Int64(garment.wears)
            ))
        }

        let requestID = UUID.v7()
        try makeOutboxRepository().enqueue(
            SyncMutation.generateOutfitTemplate(GenerateOutfitTemplateArgsDTO(
                requestId: requestID,
                template: request.template.rawValue,
                personMediaId: personID,
                garments: garments
            )).queued(),
            at: Date()
        )
        await syncCoordinator.reconcile(.mutationQueued)
        return requestID
    }
}
