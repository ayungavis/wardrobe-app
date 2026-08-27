import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct WearPrecisionTests {
    private func makeSUT() throws -> SwiftDataWardrobeItemRepository {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataWardrobeItemRepository(context: ModelContext(container))
    }

    private func midnight(of date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    @Test func theFeedNeverReplacesTheMomentWeRecordedWithThatDaysMidnight() throws {
        let sut = try makeSUT()
        let itemID = UUID()
        let worn = Date()
        let wear = WearRecord(itemID: itemID, completionID: UUID(), wornAt: worn)
        try sut.insert(
            WardrobeItem(id: itemID, category: .top, cutoutFile: "c.png", createdAt: worn, updatedAt: worn),
            fingerprint: nil,
            wear: wear
        )

        try sut.stageApply(
            wear: WearRecord(
                id: wear.id, itemID: itemID, completionID: wear.completionID,
                wornAt: midnight(of: worn)
            ),
            deletedAt: nil
        )
        try sut.commitStaged()

        #expect(
            try sut.wears(for: itemID).first?.wornAt == worn,
            "wear_record.worn_on is a date column, so the feed only ever knows the day"
        )
    }

    @Test func aCorrectionOnAnotherDayIsStillTaken() throws {
        let sut = try makeSUT()
        let itemID = UUID()
        let worn = Date()
        let wear = WearRecord(itemID: itemID, completionID: nil, wornAt: worn)
        try sut.insert(
            WardrobeItem(id: itemID, category: .top, cutoutFile: "c.png", createdAt: worn, updatedAt: worn),
            fingerprint: nil,
            wear: wear
        )
        let otherDay = midnight(of: worn.addingTimeInterval(-3 * 24 * 3600))

        try sut.stageApply(
            wear: WearRecord(id: wear.id, itemID: itemID, completionID: nil, wornAt: otherDay),
            deletedAt: nil
        )
        try sut.commitStaged()

        #expect(
            try sut.wears(for: itemID).first?.wornAt == otherDay,
            "another device moving the wear to a different day is a real correction"
        )
    }

    @Test func aWearThisDeviceHasNeverSeenArrivesAsGiven() throws {
        let sut = try makeSUT()
        let itemID = UUID()
        let day = midnight(of: Date())
        try sut.insert(
            WardrobeItem(id: itemID, category: .top, cutoutFile: "c.png", createdAt: day, updatedAt: day),
            fingerprint: nil,
            wear: nil
        )

        try sut.stageApply(
            wear: WearRecord(itemID: itemID, completionID: nil, wornAt: day), deletedAt: nil
        )
        try sut.commitStaged()

        #expect(try sut.wears(for: itemID).map(\.wornAt) == [day])
    }
}
