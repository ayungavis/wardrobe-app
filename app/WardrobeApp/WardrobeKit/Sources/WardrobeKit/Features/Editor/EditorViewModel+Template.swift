import Foundation

public extension EditorViewModel {
    var isMakingTemplate: Bool {
        templateState != .idle
    }

    func chooseTemplate(_ template: OutfitTemplate) {
        guard let requestTemplate else { return }
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
                    template: template, photo: photo, garments: placedGarments()
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

    private func placedGarments() -> [TemplateRequest.Garment] {
        let placed = document.layers.compactMap { layer -> UUID? in
            guard case let .sticker(sticker) = layer.content else { return nil }
            return sticker.art.wardrobeItemID
        }
        let items = ((try? wardrobeRepository?.items()) ?? []) ?? []
        return placed.prefix(Self.templateGarmentLimit).compactMap { id in
            guard let item = items.first(where: { $0.id == id }),
                  let cutout = try? thumbnails?.data(forFile: item.cutoutFile)
            else {
                return nil
            }
            let wears = ((try? wardrobeRepository?.wears(for: id)) ?? [])?.count ?? 0
            return TemplateRequest.Garment(cutout: cutout, name: item.name, wears: wears)
        }
    }
}
