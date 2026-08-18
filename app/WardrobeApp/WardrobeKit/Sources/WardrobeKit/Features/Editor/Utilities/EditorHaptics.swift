#if os(iOS)
    import UIKit
#endif

/// What just happened, not how it should feel.
///
/// Call sites name the event; this file decides the sensation. Left to each of
/// the twenty-odd places that want feedback, "something was deleted" would feel
/// different depending on which button you pressed.
///
/// ponytail: called straight through, no protocol and no injection. CLAUDE.md
/// classes a seam outside the process as a service, and the Taptic Engine is
/// one — but there is nothing here to assert, nothing to fake, and no failure
/// mode, so injecting it would thread a protocol through nine views to buy
/// nothing. Lift it into a service the moment something needs to observe or
/// suppress feedback.
enum EditorHaptics {
    /// Something became selected, or one discrete step was taken.
    case selection
    /// A snap engaged. Edge-triggered by the caller — §19 forbids haptics from
    /// being the only channel, so the guides and the spoken alignment carry it
    /// too.
    case latch
    /// A layer was born, or an edit was written.
    case commit
    /// A destructive drop became available — the layer is over the bin. A nudge,
    /// not a verdict: nothing has happened yet.
    case armed
    /// Locked. Deliberately unlike unlocking, which is a plain selection: the
    /// two directions should not feel the same.
    case locked
    /// Something was deleted.
    case removed
    /// Work that ran on its own finished — an export, a save to Photos. Deleting
    /// is not one of these: it is a thud, not a celebration.
    case success
    /// Work that ran on its own failed.
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

    // Held rather than built per call, which is what the prototype does — the
    // allocation is small but it is on the path of a gesture that has just
    // finished, and there is no reason to pay for it every time.
    // Nested so the generators cannot collide with the case names above —
    // `Self.selection` would have resolved to the case, not the generator.
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
