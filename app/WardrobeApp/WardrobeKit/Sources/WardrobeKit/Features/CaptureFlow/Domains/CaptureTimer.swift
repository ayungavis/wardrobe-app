public enum CaptureTimer: Int, CaseIterable, Sendable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    public var seconds: Int {
        rawValue
    }

    public var next: CaptureTimer {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .off }
        return all[(index + 1) % all.count]
    }
}
