import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct ChangeFeedTests {
    // MARK: - The cursor rule

    @Test func aFailedApplyLeavesTheCursorWhereItWas() async throws {
        let sut = try makeSUT()
        let feed = sut.feed
        let client = sut.client
        let cursor = sut.cursor
        client.pages = [page(from: 0, to: 3, kinds: ["photo", "photo", "photo"])]

        await #expect(throws: (any Error).self) {
            _ = try await feed.pull(limit: 500, applying: ThrowingApplier())
        }

        #expect(try cursor.position() == 0)
    }

    @Test func aSuccessfulApplyMovesTheCursorToNextSince() async throws {
        let sut = try makeSUT()
        let feed = sut.feed
        let client = sut.client
        let cursor = sut.cursor
        client.pages = [page(from: 0, to: 3, kinds: ["photo", "photo", "photo"]), emptyPage(at: 3)]

        let outcome = try await feed.pull(limit: 500, applying: CollectingApplier())

        #expect(outcome.records == 3)
        #expect(outcome.position == 3)
        #expect(try cursor.position() == 3)
    }

    @Test func anEmptyPageReadsAsCaughtUpRatherThanAFailure() async throws {
        let sut = try makeSUT()
        let feed = sut.feed
        let client = sut.client
        let cursor = sut.cursor
        client.pages = [emptyPage(at: 0)]

        let outcome = try await feed.pull(limit: 500, applying: CollectingApplier())

        #expect(outcome.records == 0)
        #expect(outcome.pages == 1)
        #expect(try cursor.position() == 0)
    }

    @Test func walkingOneAtATimeEndsWithTheSameRecordsAsOneBigPage() async throws {
        let kinds = ["photo", "wearRecord", "itemCutout"]

        let one = try makeSUT()
        let wide = one.feed
        let wideClient = one.client
        wideClient.pages = [page(from: 0, to: 3, kinds: kinds), emptyPage(at: 3)]
        let whole = CollectingApplier()
        _ = try await wide.pull(limit: 500, applying: whole)

        let stepwise = try makeSUT()
        let narrow = stepwise.feed
        let narrowClient = stepwise.client
        let narrowCursor = stepwise.cursor
        narrowClient.pages = [
            page(from: 0, to: 1, kinds: [kinds[0]]),
            page(from: 1, to: 2, kinds: [kinds[1]]),
            page(from: 2, to: 3, kinds: [kinds[2]]),
            emptyPage(at: 3),
        ]
        let stepped = CollectingApplier()
        let outcome = try await narrow.pull(limit: 1, applying: stepped)

        #expect(stepped.seen == whole.seen)
        #expect(outcome.pages == 4)
        #expect(try narrowCursor.position() == 3)
    }

    // MARK: - The twelve kinds

    @Test func everyKindDecodes() throws {
        let all = [
            "wardrobeItem", "itemFingerprint", "itemCutout", "itemIllustration",
            "wardrobeItemConflict", "photo", "photoDerivative", "canvasDocument",
            "challengeCompletion", "activeChallenge", "wearRecord", "accountPreference",
        ]
        let decoded = try decodePage(page(from: 0, to: Int64(all.count), kinds: all))

        #expect(decoded.changes.count == 12)
        #expect(!decoded.changes.contains {
            if case .unrecognised = $0.record {
                true
            } else {
                false
            }
        })
    }

    @Test func theConflictKindCarriesResolvedAtAndNoDeletedAt() throws {
        let decoded = try decodePage(page(from: 0, to: 1, kinds: ["wardrobeItemConflict"]))

        guard case let .wardrobeItemConflict(record) = decoded.changes[0].record else {
            Issue.record("expected a conflict")
            return
        }
        #expect(record.resolvedAt != nil)
        #expect(record.revision == 9_007_199_254_740_993)
    }

    @Test func thePreferenceKindCarriesNoIdentifier() throws {
        let decoded = try decodePage(page(from: 0, to: 1, kinds: ["accountPreference"]))

        guard case let .accountPreference(record) = decoded.changes[0].record else {
            Issue.record("expected a preference")
            return
        }
        #expect(record.recentStickerIds == ["emoji.fire"])
        #expect(Mirror(reflecting: record).children.compactMap(\.label).contains("id") == false)
    }

    @Test func aFingerprintCarriesItsFeaturePrintAsBase64() throws {
        let decoded = try decodePage(page(from: 0, to: 1, kinds: ["itemFingerprint"]))

        guard case let .itemFingerprint(record) = decoded.changes[0].record else {
            Issue.record("expected a fingerprint")
            return
        }
        #expect(record.featurePrint == Data([0x00, 0xFF, 0x10, 0x42]))
        #expect(record.colorLab == [72.5, -3.25, 18])
    }

    @Test func aWearRecordRevisionIsThirtyTwoBitsWhileAConflictIsSixtyFour() throws {
        let decoded = try decodePage(page(from: 0, to: 1, kinds: ["wearRecord"]))

        guard case let .wearRecord(record) = decoded.changes[0].record else {
            Issue.record("expected a wear record")
            return
        }
        #expect(record.revision == Int32.max)
    }

    @Test func anUnknownKindDoesNotBringDownThePageAroundIt() throws {
        let decoded = try decodePage(page(from: 0, to: 3, kinds: ["photo", "somethingNewer", "wearRecord"]))

        #expect(decoded.changes.count == 3)
        guard case let .unrecognised(kind) = decoded.changes[1].record else {
            Issue.record("expected the unknown kind to survive")
            return
        }
        #expect(kind == "somethingNewer")
    }

    // MARK: - Fixtures

    private struct SUT {
        let feed: ServerChangeFeedRepository
        let client: StubFeedClient
        let cursor: SwiftDataCursorStore
    }

    private func makeSUT() throws -> SUT {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let cursor = SwiftDataCursorStore(context: ModelContext(container))
        let client = StubFeedClient()
        return SUT(feed: ServerChangeFeedRepository(client: client, cursor: cursor), client: client, cursor: cursor)
    }

    private func decodePage(_ json: String) throws -> GetChangesResponseDTO {
        try JSONDecoder.api.decode(GetChangesResponseDTO.self, from: Data(json.utf8))
    }

    private func emptyPage(at position: Int64) -> String {
        #"{"changes":[],"nextSince":\#(position)}"#
    }

    private func page(from since: Int64, to next: Int64, kinds: [String]) -> String {
        let entries = kinds.enumerated().map { index, kind in
            #"{"kind":"\#(kind)","changeSeq":\#(since + Int64(index) + 1),"record":\#(record(kind))}"#
        }
        return #"{"changes":[\#(entries.joined(separator: ","))],"nextSince":\#(next)}"#
    }

    private func record(_ kind: String) -> String {
        wardrobeRecord(kind) ?? captureRecord(kind) ?? #"{"anything":true}"#
    }

    private func wardrobeRecord(_ kind: String) -> String? {
        switch kind {
        case "wardrobeItem":
            #"""
            {"id":"\#(fixtureID)","category":"top","name":null,"color":null,"garmentType":null,
             "description":null,"attributeRevisions":{},"illustrationState":"none",
             "currentIllustrationId":null,"changeSeq":1,"deletedAt":null}
            """#
        case "itemFingerprint":
            #"""
            {"id":"\#(fixtureID)","itemId":"\#(fixtureID)","version":"v1",
             "colorLab":[72.5,-3.25,18],"aspectRatio":0.75,"featurePrint":"AP8QQg==",
             "maskQuality":0.82,"sourcePhotoId":null,"changeSeq":1,"deletedAt":null}
            """#
        case "itemCutout":
            #"""
            {"id":"\#(fixtureID)","itemId":"\#(fixtureID)","mediaObjectId":"\#(fixtureID)",
             "sourcePhotoId":null,"changeSeq":1,"deletedAt":null}
            """#
        case "itemIllustration":
            #"""
            {"id":"\#(fixtureID)","itemId":"\#(fixtureID)","mediaObjectId":"\#(fixtureID)",
             "model":"m","promptVersion":"p1","styleVersion":"s1","changeSeq":1,"deletedAt":null}
            """#
        case "wardrobeItemConflict":
            #"""
            {"id":"\#(fixtureID)","itemId":"\#(fixtureID)","field":"name","value":"coat",
             "revision":9007199254740993,"originDevice":null,"resolvedAt":"\#(fixtureStamp)",
             "changeSeq":1}
            """#
        case "wearRecord":
            #"""
            {"id":"\#(fixtureID)","itemId":"\#(fixtureID)","wornOn":"2026-08-25",
             "revision":2147483647,"completionId":null,"sourcePhotoId":null,
             "changeSeq":1,"deletedAt":null}
            """#
        default: nil
        }
    }

    private func captureRecord(_ kind: String) -> String? {
        switch kind {
        case "photo":
            #"""
            {"id":"\#(fixtureID)","mediaObjectId":"\#(fixtureID)","source":"capture",
             "capturedAt":null,"changeSeq":1,"deletedAt":null}
            """#
        case "photoDerivative":
            #"""
            {"id":"\#(fixtureID)","photoId":"\#(fixtureID)","mediaObjectId":"\#(fixtureID)",
             "changeSeq":1,"deletedAt":null}
            """#
        case "canvasDocument":
            #"""
            {"id":"\#(fixtureID)","completionId":"\#(fixtureID)","derivativeId":"\#(fixtureID)",
             "schemaVersion":1,"mediaObjectId":"\#(fixtureID)","historyMediaObjectId":null,
             "historyStepCount":null,"changeSeq":1,"deletedAt":null}
            """#
        case "challengeCompletion":
            #"""
            {"id":"\#(fixtureID)","cardId":"\#(fixtureID)","status":"canonical",
             "localDate":"2026-08-25","timeZone":"Asia/Makassar","completedAt":"\#(fixtureStamp)",
             "photoId":null,"currentDerivativeId":null,"changeSeq":1,"deletedAt":null}
            """#
        case "activeChallenge":
            #"""
            {"id":"\#(fixtureID)","cardId":"\#(fixtureID)","localDate":"2026-08-25",
             "timeZone":"Asia/Makassar","acceptedAt":"\#(fixtureStamp)","photoId":null,
             "changeSeq":1,"deletedAt":null}
            """#
        case "accountPreference":
            #"""
            {"recentStickerIds":["emoji.fire"],"lastTextStyle":{},"onboardingCompletedAt":null,
             "changeSeq":1,"deletedAt":null}
            """#
        default: nil
        }
    }

    private var fixtureID: String {
        "00000000-0000-4000-8000-000000000001"
    }

    private var fixtureStamp: String {
        "2026-08-25T04:00:00Z"
    }
}

// MARK: - Doubles

@MainActor
private final class StubFeedClient: AuthenticatedAPIClient {
    var pages: [String] = []
    private(set) var requested: [Int64] = []

    func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response {
        if let changes = endpoint as? GetChangesEndpoint {
            requested.append(changes.since)
        }
        guard !pages.isEmpty else { throw AppError.unexpected }
        return try JSONDecoder.api.decode(Route.Response.self, from: Data(pages.removeFirst().utf8))
    }

    func send<Route: RequestEndpoint>(_: Route) async throws -> Route.Response {
        throw AppError.unexpected
    }
}

@MainActor
private final class CollectingApplier: ChangeApplier {
    private(set) var seen: [Int64] = []

    func apply(_ changes: [ChangeDTO]) throws {
        seen.append(contentsOf: changes.map(\.changeSeq))
    }
}

@MainActor
private final class ThrowingApplier: ChangeApplier {
    func apply(_: [ChangeDTO]) throws {
        throw AppError.unexpected
    }
}
