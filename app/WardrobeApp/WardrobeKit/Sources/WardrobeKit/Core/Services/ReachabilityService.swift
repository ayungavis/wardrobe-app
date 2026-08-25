import Foundation
import Network

// ponytail: only the unsatisfied -> satisfied edge counts. NWPathMonitor also
// reports interface, cost, and constraint changes, and reconciling on every one
// of those reconciles repeatedly while roaming between networks.
struct ReachabilityEdge {
    private var wasSatisfied = true

    mutating func recovered(isSatisfied: Bool) -> Bool {
        let recovered = isSatisfied && !wasSatisfied
        wasSatisfied = isSatisfied
        return recovered
    }
}

@MainActor
public protocol ReachabilityService: AnyObject {
    func observe(onRestored: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
public final class PathReachabilityService: ReachabilityService {
    private let monitor = NWPathMonitor()
    private var task: Task<Void, Never>?
    private var edge = ReachabilityEdge()

    public init() {}

    public func observe(onRestored: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [monitor] in
            for await path in monitor where edge.recovered(isSatisfied: path.status == .satisfied) {
                onRestored()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
