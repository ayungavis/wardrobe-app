import SwiftUI

// ponytail: strings here are deliberately NOT localized (`Text(verbatim:)`).
// The sheet never reaches an App Store build, so no user ever reads them.

/// Developer configuration sheet — long-press the Challenge screen to open it.
struct DevMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: DevMenuViewModel
    @State private var isResetConfirmationPresented = false
    /// Called after an action mutates a repository, so the screen behind the sheet
    /// updates right away instead of waiting for dismissal.
    private let onStateChanged: () -> Void

    init(viewModel: DevMenuViewModel, onStateChanged: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel)
        self.onStateChanged = onStateChanged
    }

    var body: some View {
        NavigationStack {
            List {
                DevStateSection(summary: viewModel.summary)
                DevTodaySection(lastAction: viewModel.lastAction) {
                    isResetConfirmationPresented = true
                }
            }
            .navigationTitle(Text(verbatim: "Dev menu"))
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
                .confirmationDialog(
                    Text(verbatim: "Reset today's challenge?"),
                    isPresented: $isResetConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        viewModel.resetToday()
                        onStateChanged()
                    } label: {
                        Text(verbatim: "Reset")
                    }
                    Button(role: .cancel) {} label: {
                        Text("common.cancel", bundle: .module)
                    }
                } message: {
                    Text(verbatim: "Deletes today's completion, the active challenge, and their photos.")
                }
        }
        .presentationDetents([.medium, .large])
        .task { viewModel.refresh() }
    }
}

private struct DevStateSection: View {
    let summary: DevStateSummary

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(summary.completionCount)")
            } label: {
                Text(verbatim: "Completions stored")
            }
            LabeledContent {
                Text(verbatim: summary.hasCompletedToday ? "yes" : "no")
            } label: {
                Text(verbatim: "Completed today")
            }
            LabeledContent {
                Text(verbatim: activeDescription)
            } label: {
                Text(verbatim: "Active challenge")
            }
        } header: {
            Text(verbatim: "State")
        }
    }

    private var activeDescription: String {
        guard summary.hasActiveChallenge else { return "none" }
        return summary.activeHasPhoto ? "yes (with photo)" : "yes"
    }
}

private struct DevTodaySection: View {
    let lastAction: String?
    let onReset: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onReset) {
                Text(verbatim: "Reset today's challenge")
            }
        } header: {
            Text(verbatim: "Today")
        } footer: {
            // New dev actions go here as extra rows — one method on the view
            // model, one Button.
            Text(verbatim: lastAction ?? "Reopens the deck as if today had not started.")
        }
    }
}

#Preview {
    DevMenuView(viewModel: AppContainer().makeDevMenuViewModel(), onStateChanged: {})
}
