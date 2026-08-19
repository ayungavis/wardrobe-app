import DesignSystem
import SwiftUI

/// A short statement about the draft, under the close button.
///
/// A statement and nothing else — no buttons. Discarding already lives on the
/// editor's close button sixty points above this, with its confirmation dialog;
/// a second door to the same dialog, sitting next to a dismiss control that
/// looks just like it, is one destructive tap waiting to be misread.
///
/// It also has no "saved" state. The bottom bar's Save pill already means "the
/// picture is in Photos" and already says "Saved"; a second thing on the same
/// screen claiming that word about something else is how two different facts
/// get confused for one. Silence here means the draft is being kept.
struct DraftBannerView: View {
    enum Kind {
        /// §17: an unconfirmed device-only draft was restored and stays unsynced.
        /// News about the past — it goes away on its own.
        case restored
        /// The last write did not land, the one draft state with no other voice.
        /// A condition, not news: it stays until a write succeeds.
        case writeFailed
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: kind == .restored ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill")
                .foregroundStyle(kind == .restored ? AppColor.onMedia : AppColor.warning)

            Text(kind == .restored ? "editor.draft.restored" : "editor.draft.failed", bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.onMedia)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.draft.banner")
    }
}
