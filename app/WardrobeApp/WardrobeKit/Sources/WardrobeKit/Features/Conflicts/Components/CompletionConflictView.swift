import DesignSystem
import SwiftUI

struct CompletionConflictView: View {
    let group: ConflictsViewModel.CompletionDayConflict
    let previewData: (CompletedChallenge) -> Data?
    let onChoose: (CompletedChallenge) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(group.day, style: .date)
                .font(.headline)
            Text("conflicts.completion.explainer", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(group.completions) { completion in
                    candidate(completion)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func candidate(_ completion: CompletedChallenge) -> some View {
        VStack(spacing: Spacing.sm) {
            Group {
                if let data = previewData(completion) {
                    DownsampledPhotoView(data: data, maxPixel: 600)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(Text("conflicts.completion.photo", bundle: .module))

            Text(completion.completedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)

            if completion.status == .canonical {
                Text("conflicts.completion.current", bundle: .module)
                    .font(.caption.bold())
            } else {
                Button {
                    onChoose(completion)
                } label: {
                    Text("conflicts.completion.choose", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
