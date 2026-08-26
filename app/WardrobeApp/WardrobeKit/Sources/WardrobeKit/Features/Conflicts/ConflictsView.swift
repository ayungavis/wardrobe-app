import DesignSystem
import SwiftUI

public struct ConflictsView: View {
    @State private var viewModel: ConflictsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ConflictsViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("conflicts.empty", bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                } else {
                    conflictList
                }
            }
            .navigationTitle(Text("conflicts.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("common.done", bundle: .module)
                        }
                    }
                }
        }
        .task { viewModel.load() }
    }

    private var conflictList: some View {
        List {
            if !viewModel.completionConflicts.isEmpty {
                Section {
                    ForEach(viewModel.completionConflicts) { group in
                        CompletionConflictView(
                            group: group,
                            previewData: { viewModel.previewData(for: $0) },
                            onChoose: { try? viewModel.choose($0) }
                        )
                    }
                } header: {
                    Text("conflicts.completions.header", bundle: .module)
                }
            }
            if !viewModel.itemConflicts.isEmpty {
                Section {
                    ForEach(viewModel.itemConflicts) { display in
                        ItemConflictRowView(
                            display: display,
                            onKeepCurrent: { viewModel.keepCurrent(display) },
                            onUseIncoming: { viewModel.useIncoming(display) }
                        )
                    }
                } header: {
                    Text("conflicts.items.header", bundle: .module)
                }
            }
        }
    }
}
