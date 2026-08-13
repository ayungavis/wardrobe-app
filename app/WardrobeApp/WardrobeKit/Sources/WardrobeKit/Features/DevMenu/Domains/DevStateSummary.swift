import Foundation

public struct DevStateSummary: Equatable, Sendable {
    public var completionCount = 0
    public var hasCompletedToday = false
    public var hasActiveChallenge = false
    public var activeHasPhoto = false
}
