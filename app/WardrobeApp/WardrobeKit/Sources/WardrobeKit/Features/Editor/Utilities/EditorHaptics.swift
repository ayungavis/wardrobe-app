#if os(iOS)
    import UIKit
#endif

// ponytail: called straight through, no protocol and no injection.
// classes a seam outside the process as a service, and the Taptic Engine is
// one — but there is nothing here to assert, nothing to fake, and no failure
// mode, so injecting it would thread a protocol through nine views to buy
// nothing. Lift it into a service the moment something needs to observe or
// suppress feedback.
enum EditorHaptics {
    case selection
    case latch
    case commit
    case armed
    case locked
    case removed
    case success
    case failure

    @MainActor
    func play() {
        #if os(iOS)
            switch self {
            case .selection, .latch:
                Generators.selection.selectionChanged()
            case .commit, .armed:
                Generators.light.impactOccurred()
            case .locked:
                Generators.rigid.impactOccurred()
            case .removed:
                Generators.medium.impactOccurred()
            case .success:
                Generators.notification.notificationOccurred(.success)
            case .failure:
                Generators.notification.notificationOccurred(.error)
            }
        #endif
    }

    #if os(iOS)
        @MainActor
        private enum Generators {
            static let selection = UISelectionFeedbackGenerator()
            static let light = UIImpactFeedbackGenerator(style: .light)
            static let medium = UIImpactFeedbackGenerator(style: .medium)
            static let rigid = UIImpactFeedbackGenerator(style: .rigid)
            static let notification = UINotificationFeedbackGenerator()
        }
    #endif
}
