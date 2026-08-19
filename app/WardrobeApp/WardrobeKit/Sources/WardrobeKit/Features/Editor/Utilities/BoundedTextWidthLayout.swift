import CoreGraphics
import SwiftUI

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
        for measurement in subviews.dropFirst() {
            measurement.place(at: bounds.origin, proposal: .unspecified)
        }
    }
}
