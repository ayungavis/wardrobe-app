import CoreGraphics
import SwiftUI

/// Sizes the composer's text box to the text inside it, clamped to a range.
///
/// A plain `TextField` fills whatever width it is given, which would leave
/// alignment with nothing to align against and stretch the background pill the
/// full width of the card. This measures the text and hugs it instead, so the
/// pill wraps the words and left/right alignment visibly move them.
///
/// Two subviews, in order: the interactive stack, then a hidden copy of the
/// text used only for measuring. They must stay in that order — the second one
/// is what decides the width.
struct BoundedTextWidthLayout: Layout {
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let measurement = subviews.last else { return .zero }

        let available = min(max(proposal.width ?? maximumWidth, 0), maximumWidth)
        let measured = measurement.sizeThatFits(.unspecified).width
        let width = min(max(measured, minimumWidth), available)
        let height = measurement.sizeThatFits(ProposedViewSize(width: width, height: nil)).height

        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let content = subviews.first else { return }
        content.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
        // The measuring copy is hidden; it only ever needed to be asked its size.
        for measurement in subviews.dropFirst() {
            measurement.place(at: bounds.origin, proposal: .unspecified)
        }
    }
}
