import Foundation
import Testing
@testable import WardrobeKit

struct SyncStateTests {
    // MARK: - The rule the whole ticket exists for

    @Test func anAcknowledgedMutationWithUnstampedMediaIsNotSynced() {
        let state = SyncState.derive(
            queuedAt: Date(),
            mutation: nil,
            mediaRows: [makeMediaRow()]
        )

        #expect(state != .synced, "FR-068: records are not fully synced until their objects upload")
        #expect(state == .pending)
    }

    @Test func aFailedMediaRowSurfacesAsFailedEvenWithTheMutationGone() {
        let row = makeMediaRow(state: .failed, code: "unavailable")

        let state = SyncState.derive(queuedAt: Date(), mutation: nil, mediaRows: [row])

        #expect(state == .failed(code: "unavailable", reference: row.id))
    }

    // MARK: - The other three states

    @Test func aRecordNeverQueuedIsLocalOnly() {
        #expect(SyncState.derive(queuedAt: nil, mutation: nil, mediaRows: []) == .localOnly)
    }

    @Test func aQueuedMutationIsPendingNotBlockingAnything() {
        let state = SyncState.derive(queuedAt: Date(), mutation: makeMutation(), mediaRows: [])

        #expect(state == .pending)
    }

    @Test func aFailedMutationCarriesItsCodeAndReference() {
        let mutation = makeMutation(state: .failed, code: "not_found")

        let state = SyncState.derive(queuedAt: Date(), mutation: mutation, mediaRows: [])

        #expect(state == .failed(code: "not_found", reference: mutation.id))
    }

    @Test func everythingAcknowledgedAndStampedIsSynced() {
        #expect(SyncState.derive(queuedAt: Date(), mutation: nil, mediaRows: []) == .synced)
    }

    // MARK: - §18.12: the diagnostic carries no user content

    @Test func theDiagnosticNeverCarriesUserContent() {
        let mutation = OutboxEnvelope(
            id: UUID(), name: "completeChallenge",
            payload: Data(#"{"name":"my secret jacket"}"#.utf8),
            createdAt: Date(), attempts: 5, state: .failed,
            nextAttemptAt: Date(), lastErrorCode: "server_rejected"
        )

        guard case let .failed(code, reference) = SyncState.derive(
            queuedAt: Date(), mutation: mutation, mediaRows: []
        ) else {
            Issue.record("expected failed")
            return
        }

        #expect(!code.contains("jacket"), "the payload must never reach the diagnostic")
        #expect(reference == mutation.id)
    }

    // MARK: - Fixtures

    private func makeMutation(
        state: OutboxEnvelope.State = .pending,
        code: String? = nil
    ) -> OutboxEnvelope {
        OutboxEnvelope(
            id: UUID(), name: "completeChallenge", payload: Data("{}".utf8),
            createdAt: Date(), attempts: 0, state: state,
            nextAttemptAt: Date(), lastErrorCode: code
        )
    }

    private func makeMediaRow(
        state: OutboxEnvelope.State = .pending,
        code: String? = nil
    ) -> MediaUpload {
        MediaUpload(
            id: UUID(), ownerID: UUID(), kind: .cutout, contentType: "image/png",
            source: .inline(Data([0x01])), createdAt: Date(),
            state: state, lastErrorCode: code
        )
    }
}
