import Foundation

public extension EditorViewModel {
    var isMakingTemplate: Bool {
        templateState != .idle
    }

    var canAskForTemplate: Bool {
        !isMakingTemplate && review?.isScanning != true
    }

    func chooseTemplate(_ template: OutfitTemplate) {
        guard let requestTemplate else { return }
        guard review?.isScanning != true else { return }
        guard !needsUploadConsent else {
            isConsentPresented = true
            return
        }
        guard let photoID = challenge.photoID,
              let photo = try? photoRepository.loadOriginal(id: photoID)
        else {
            alertError = .photoImportFailed
            return
        }

        lastTemplate = template
        templateTimedOut = false
        templateState = .loading
        templateTask = Task {
            do {
                let request = TemplateRequest(
                    template: template, photo: photo, garments: scannedGarments()
                )
                pendingTemplateID = try await requestTemplate(request)
                try await waitForTemplate()
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.ui)
                templateState = .failed(AppError(wrapping: error))
            }
        }
    }

    func cancelTemplate() {
        templateTask?.cancel()
        templateTask = nil
        pendingTemplateID = nil
        templateTimedOut = false
        templateState = .idle
    }

    func retryTemplate() {
        guard let lastTemplate else { return }
        chooseTemplate(lastTemplate)
    }

    func adoptTemplateIfArrived() {
        guard case .loading = templateState, let request = pendingTemplateID else { return }
        guard let bytes = try? photoRepository.loadOriginal(id: request) else { return }
        setBackgroundPhoto(bytes)
        templateState = .idle
        pendingTemplateID = nil
    }

    // ponytail: the editor waits by asking rather than being told; a push
    // notification replaces this the day one exists.
    private func waitForTemplate() async throws {
        for _ in 0 ..< Self.templateAttempts {
            try await sleep(.seconds(3))
            try Task.checkCancellation()
            adoptTemplateIfArrived()
            guard case .loading = templateState else { return }
        }
        templateTimedOut = true
        templateState = .failed(.unavailable)
    }

    private func scannedGarments() -> [TemplateRequest.Garment] {
        guard let review else { return [] }
        return review.activeGarments.prefix(Self.templateGarmentLimit).compactMap { garment in
            guard let cutout = try? thumbnails?.data(forFile: garment.cutoutFile) else { return nil }
            return TemplateRequest.Garment(
                cutout: cutout, name: garment.name, wears: wearsAfterToday(garment)
            )
        }
    }

    private func wearsAfterToday(_ garment: ScannedGarment) -> Int {
        guard case let .existing(itemID) = garment.decision else { return 1 }
        let existing = ((try? wardrobeRepository?.wears(for: itemID)) ?? [])?.count ?? 0
        return existing + 1
    }
}
