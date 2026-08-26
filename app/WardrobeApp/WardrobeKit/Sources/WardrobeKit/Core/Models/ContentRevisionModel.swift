import Foundation
import Observation

// ponytail: a counter rather than a change feed of its own. Views reload on a
// new value through .task(id:); nothing needs to know what changed, only that
// something did. Give it typed events if a screen ever needs to reload for one
// kind of change and not another.
@MainActor
@Observable
public final class ContentRevisionModel {
    public private(set) var revision = 0

    public init() {}

    public func bump() {
        revision += 1
    }
}
