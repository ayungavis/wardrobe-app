import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct AwaitingIllustrationTests {
    private func makeContainer(statuses: [ItemStatus]) -> AppContainer {
        let container = AppContainer()
        let repository = container.makeWardrobeItemRepository()
        try? repository.deleteAll()
        for status in statuses {
            let id = UUID()
            var item = WardrobeItem(
                id: id, category: .top, cutoutFile: "\(id.uuidString).png",
                createdAt: Date(), updatedAt: Date()
            )
            item.status = status
            try? repository.insert(item, fingerprint: nil, wear: nil)
        }
        return container
    }

    @Test func pendingAndProcessingItemsAreWorthWaitingFor() {
        #expect(makeContainer(statuses: [.ready, .pending]).isAwaitingIllustration)
        #expect(makeContainer(statuses: [.processing]).isAwaitingIllustration)
    }

    @Test func undrawnReadyAndFailedItemsAreNot() {
        let container = makeContainer(statuses: [.undrawn, .ready, .failed])

        #expect(
            !container.isAwaitingIllustration,
            "undrawn means nothing was ever asked for; counting it polls the network forever"
        )
    }

    @Test func anEmptyWardrobeWaitsForNothing() {
        #expect(!makeContainer(statuses: []).isAwaitingIllustration)
    }
}
