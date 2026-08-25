import Foundation

// ponytail: the applier speaks in DTOs because nothing maps the twelve kinds to
// domain types yet — T45 owns that and will know which ones it needs. It must
// write through the store's own ModelContext and never save; the cursor's save
// is what makes the page and its position land together.
@MainActor
protocol ChangeApplier: AnyObject {
    func apply(_ changes: [ChangeDTO]) throws
}

// ponytail: T38 reads the feed and moves the cursor; nothing applies yet. T45
// replaces this with the real restore, which is the ticket that knows which
// kinds it needs and what a conflict with a local edit means.
@MainActor
final class NoopChangeApplier: ChangeApplier {
    func apply(_: [ChangeDTO]) throws {}
}
