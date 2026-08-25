import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct SyncEndpointTests {
    // MARK: - The present-but-null rule

    @Test func aClearedFieldKeepsItsKeyWithANullValue() throws {
        let json = try encoded(ItemFieldDTO(value: nil, rev: 3))

        #expect(json.contains("\"value\":null"))
        #expect(json.contains("\"rev\":3"))
    }

    @Test func anAbsentFieldIsOmittedEntirely() throws {
        let json = try encoded(UpsertItemArgsDTO(id: UUID(), name: ItemFieldDTO(value: "coat", rev: 1)))

        #expect(json.contains("\"name\""))
        #expect(!json.contains("\"color\""))
        #expect(!json.contains("\"cutout\""))
    }

    // MARK: - The cursor rule

    @Test func aWriteResponseCarriesNothingButResults() throws {
        let response = try decoded(#"{"results":[]}"#)
        let fields = Mirror(reflecting: response).children.compactMap(\.label)

        #expect(fields == ["results"])
    }

    @Test func aCursorSmuggledIntoAWriteResponseIsIgnored() throws {
        let response = try decoded(#"{"results":[],"nextSince":99}"#)

        #expect(Mirror(reflecting: response).children.compactMap(\.label) == ["results"])
        #expect(response.results.isEmpty)
    }

    // MARK: - Batching

    @Test func aBatchOfOneHundredAndOneIsSplit() throws {
        let batches = try SyncBatching.batches(from: (0 ..< 101).map { _ in makeMutation() })

        #expect(batches.count == 2)
        #expect(batches.first?.count == SyncBatching.maxMutations)
        #expect(batches.last?.count == 1)
        #expect(batches.reduce(0) { $0 + $1.count } == 101)
    }

    @Test func aBatchOfExactlyOneHundredIsNotSplit() throws {
        let batches = try SyncBatching.batches(from: (0 ..< 100).map { _ in makeMutation() })

        #expect(batches.count == 1)
    }

    @Test func anOversizedMutationShipsAloneRatherThanBeingDropped() throws {
        let huge = makeMutation(payload: String(repeating: "x", count: SyncBatching.maxBytes + 1024))
        let batches = try SyncBatching.batches(from: [makeMutation(), huge, makeMutation()])

        #expect(batches.flatMap(\.self).count == 3)
        let alone = try #require(batches.first { $0.contains(huge) })
        #expect(alone.count == 1)
    }

    @Test func noMutationsMeansNoRequest() throws {
        #expect(try SyncBatching.batches(from: []).isEmpty)
    }

    // MARK: - Requeue

    @Test func onlyTheFailedLineComesBack() throws {
        let failed = UUID()
        let response = try decoded("""
        {"results":[
          {"id":"\(UUID().uuidString)","name":"upsertItem","status":"applied","record":{"id":1}},
          {"id":"\(failed.uuidString)","name":"deleteItem","status":"failed",
           "error":{"code":"not_found","message":"gone"}},
          {"id":"\(UUID().uuidString)","name":"upsertItem","status":"applied","record":{}}
        ]}
        """)

        #expect(SyncBatching.failedIdentifiers(in: response) == [failed])
    }

    @Test func anUnknownStatusFailsTheWholeResponseRatherThanLosingALine() {
        #expect(throws: (any Error).self) {
            try decoded("""
            {"results":[{"id":"\(UUID().uuidString)","name":"upsertItem","status":"deferred"}]}
            """)
        }
    }

    // MARK: - Names cannot drift from payloads

    @Test func everyMutationNamesItselfFromItsCase() {
        #expect(SyncMutation.deleteItem(DeleteItemArgsDTO(id: UUID())).name == "deleteItem")
        #expect(SyncMutation.upsertItem(UpsertItemArgsDTO(id: UUID())).name == "upsertItem")
        #expect(SyncMutation.upsertPreferences(UpsertPreferencesArgsDTO()).name == "upsertPreferences")
        #expect(SyncMutation.resolveCompletion(
            ResolveCompletionArgsDTO(completionId: UUID())
        ).name == "resolveCompletion")
    }

    @Test func aQueuedMutationCarriesItsOwnArguments() throws {
        let id = UUID()
        let queued = try SyncMutation.deleteItem(DeleteItemArgsDTO(id: id)).queued()

        #expect(queued.name == "deleteItem")
        #expect(String(bytes: queued.payload, encoding: .utf8)?.contains(id.uuidString) == true)
    }

    // MARK: - JSON round trip

    @Test func integersSurviveTheRoundTripWithoutBecomingDoubles() throws {
        let value = try JSONDecoder.api.decode(JSONValue.self, from: Data(#"{"seq":9007199254740993}"#.utf8))

        #expect(value == .object(["seq": .int(9_007_199_254_740_993)]))
    }

    // MARK: - Fixtures

    private func decoded(_ json: String) throws -> PostSyncResponseDTO {
        try JSONDecoder.api.decode(PostSyncResponseDTO.self, from: Data(json.utf8))
    }

    private func makeMutation(payload: String = "{}") -> MutationRequestDTO {
        MutationRequestDTO(id: UUID(), name: "upsertItem", args: .object(["p": .string(payload)]))
    }

    private func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder.api
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try #require(String(bytes: encoder.encode(value), encoding: .utf8))
    }
}
