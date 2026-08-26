import Foundation

public extension HistoryViewModel {
    func save(_ completion: CompletedChallenge) {
        guard let data = previewData(for: completion) else {
            alertError = .photoSaveFailed
            return
        }
        shareTask = Task { [saver] in
            do {
                try await saver.save(data)
                didSave = true
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = AppError(wrapping: error)
            }
        }
    }

    func acknowledgeSave() {
        didSave = false
    }

    // ponytail: uploaded fresh on every share rather than reusing the derivative
    // id CompletionSyncPlanner mints, which lives inside outbox arguments and is
    // gone once the entry is acknowledged. The object is tied to no sync record
    // and goes with the account; give it an owner if these start piling up.
    func share(_ completion: CompletedChallenge, side: CGFloat = 720) {
        guard let data = previewData(for: completion), let media else {
            alertError = .photoSaveFailed
            return
        }
        isSharePresented = true
        share = .loading
        shareTask = Task {
            do {
                let id = UUID.v7()
                try await media.upload(data, id: id, kind: .derivative, contentType: "image/jpeg")
                let url = try await media.downloadURL(for: id)
                guard let qr = QRCode.image(for: url.absoluteString, side: side) else {
                    throw AppError.unexpected
                }
                try Task.checkCancellation()
                share = .loaded(CompletionShare(url: url, qr: qr))
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.ui)
                share = .failed(AppError(wrapping: error))
            }
        }
    }
}
