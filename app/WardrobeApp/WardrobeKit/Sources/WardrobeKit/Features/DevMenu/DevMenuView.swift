import SwiftUI

// ponytail: strings here are deliberately NOT localized (`Text(verbatim:)`).
// The sheet never reaches an App Store build, so no user ever reads them.

struct DevMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: DevMenuViewModel
    @State private var isResetConfirmationPresented = false
    @State private var isHistoryResetConfirmationPresented = false
    @State private var isWardrobeResetConfirmationPresented = false
    @State private var isOnboardingResetConfirmationPresented = false
    @State private var isBulkScanPresented = false
    @State private var isBenchmarkPresented = false
    private let onStateChanged: () -> Void
    private let makeReview: () -> GarmentReviewModel
    private let makeBenchmark: () -> MatchBenchmarkViewModel

    init(
        viewModel: DevMenuViewModel,
        makeReview: @escaping () -> GarmentReviewModel,
        makeBenchmark: @escaping () -> MatchBenchmarkViewModel,
        onStateChanged: @escaping () -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.makeReview = makeReview
        self.makeBenchmark = makeBenchmark
        self.onStateChanged = onStateChanged
    }

    var body: some View {
        NavigationStack {
            List {
                DevStateSectionView(summary: viewModel.summary)
                DevSessionSectionView(
                    baseURL: viewModel.baseURL,
                    state: viewModel.sessionState,
                    health: viewModel.healthState,
                    onReload: { viewModel.loadSession() },
                    onWhoami: { viewModel.loadSession(callingWhoami: true) },
                    onHealth: { viewModel.checkHealth() }
                )
                DevMediaSectionView(
                    state: viewModel.mediaState,
                    onRoundTrip: { viewModel.runMediaRoundTrip() }
                )
                DevDiagnosticsSectionView(
                    entries: viewModel.diagnostics,
                    onClear: { viewModel.clearDiagnostics() }
                )
                DevSyncSectionView(
                    cursor: viewModel.cursor,
                    state: viewModel.pullState,
                    reconcile: viewModel.reconcileState,
                    onPull: { viewModel.pullChanges() },
                    onReconcile: { viewModel.reconcileNow() }
                )
                DevOutboxSectionView(
                    entries: viewModel.outbox,
                    onRetryFailed: { viewModel.retryFailedOutbox() },
                    onClear: { viewModel.clearOutbox() }
                )
                DevTodaySectionView(lastAction: viewModel.lastAction) {
                    isResetConfirmationPresented = true
                }
                DevHistorySectionView {
                    isHistoryResetConfirmationPresented = true
                }
                DevOnboardingSectionView {
                    isOnboardingResetConfirmationPresented = true
                }
                DevWardrobeSectionView(
                    onScan: { isBulkScanPresented = true },
                    onBenchmark: { isBenchmarkPresented = true },
                    onReset: { isWardrobeResetConfirmationPresented = true }
                )
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
                .confirmationDialog(
                    Text(verbatim: "Reset all history?"),
                    isPresented: $isHistoryResetConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        viewModel.resetHistory()
                        onStateChanged()
                    } label: {
                        Text(verbatim: "Reset")
                    }
                    Button(role: .cancel) {} label: {
                        Text("common.cancel", bundle: .module)
                    }
                } message: {
                    Text(verbatim: "Deletes every completed challenge and its photos. The wardrobe is left alone.")
                }
                .confirmationDialog(
                    Text(verbatim: "Reset wardrobe?"),
                    isPresented: $isWardrobeResetConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        viewModel.resetWardrobe()
                        onStateChanged()
                    } label: {
                        Text(verbatim: "Reset")
                    }
                    Button(role: .cancel) {} label: {
                        Text("common.cancel", bundle: .module)
                    }
                } message: {
                    Text(verbatim: "Deletes every wardrobe item, its wear history, and its cut-out image.")
                }
                .confirmationDialog(
                    Text(verbatim: "Reset onboarding?"),
                    isPresented: $isOnboardingResetConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        dismiss()
                        Task { await viewModel.resetOnboarding() }
                    } label: {
                        Text(verbatim: "Reset")
                    }
                    Button(role: .cancel) {} label: {
                        Text("common.cancel", bundle: .module)
                    }
                } message: {
                    Text(verbatim: "Signs out of Apple and reopens onboarding right away. "
                        + "Challenges and the wardrobe are left alone.")
                }
        }
        .sheet(isPresented: $isBulkScanPresented, onDismiss: onStateChanged) {
            AddByPhotosView(review: makeReview())
        }
        .sheet(isPresented: $isBenchmarkPresented) {
            MatchBenchmarkView(viewModel: makeBenchmark())
        }
        .presentationDetents([.medium, .large])
        .task { viewModel.refresh() }
    }
}

private struct DevStateSectionView: View {
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
            LabeledContent {
                Text(verbatim: "\(summary.wardrobeItemCount)")
            } label: {
                Text(verbatim: "Wardrobe items")
            }
            LabeledContent {
                Text(verbatim: "\(summary.fingerprintCount)")
            } label: {
                Text(verbatim: "Fingerprints")
            }
            LabeledContent {
                Text(verbatim: summary.hasCompletedOnboarding ? "done" : "pending")
            } label: {
                Text(verbatim: "Onboarding")
            }
            LabeledContent {
                Text(verbatim: summary.isSignedIn ? "yes" : "no")
            } label: {
                Text(verbatim: "Signed in with Apple")
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

private struct DevTodaySectionView: View {
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
            Text(verbatim: lastAction ?? "Reopens the deck as if today had not started.")
        }
    }
}

private struct DevHistorySectionView: View {
    let onReset: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onReset) {
                Text(verbatim: "Reset all history")
            }
        } header: {
            Text(verbatim: "History")
        } footer: {
            Text(verbatim: "Clears every completed challenge, not just today's. "
                + "Wear counts survive; use Reset wardrobe.")
        }
    }
}

private struct DevOnboardingSectionView: View {
    let onReset: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onReset) {
                Text(verbatim: "Reset onboarding")
            }
        } header: {
            Text(verbatim: "Onboarding")
        } footer: {
            Text(verbatim: "Clears the Apple account from the keychain and sends you "
                + "back to step 1 without a restart.")
        }
    }
}

private struct DevWardrobeSectionView: View {
    let onScan: () -> Void
    let onBenchmark: () -> Void
    let onReset: () -> Void

    var body: some View {
        Section {
            Button(action: onScan) {
                Text(verbatim: "Bulk scan photos")
            }
            Button(action: onBenchmark) {
                Text(verbatim: "Match benchmark")
            }
            Button(role: .destructive, action: onReset) {
                Text(verbatim: "Reset wardrobe")
            }
        } header: {
            Text(verbatim: "Wardrobe")
        } footer: {
            Text(verbatim: "Clears every scanned garment so you can start from an empty wardrobe.")
        }
    }
}

#Preview {
    let container = AppContainer()
    DevMenuView(
        viewModel: container.makeDevMenuViewModel(),
        makeReview: { container.makeGarmentReviewModel() },
        makeBenchmark: { container.makeMatchBenchmarkViewModel() },
        onStateChanged: {}
    )
}
